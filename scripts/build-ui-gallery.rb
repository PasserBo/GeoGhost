#!/usr/bin/env ruby
# Builds the UI gallery: one static page showing every screen and state of ui/screen.yaml with its
# snapshot from ui/snapshots/, for people who don't open Xcode (designers, reviewers).
#
#   ruby scripts/build-ui-gallery.rb <output-dir>
#
# The docs workflow runs this and publishes the result at <site>/ui/. To look at it locally:
#   ruby scripts/build-ui-gallery.rb build/ui-gallery && open build/ui-gallery/index.html
require "yaml"
require "cgi"
require "fileutils"

root = File.expand_path("..", __dir__)
out = ARGV[0] or abort("usage: build-ui-gallery.rb <output-dir>")
spec = YAML.load_file(File.join(root, "ui/screen.yaml"))
events = YAML.load_file(File.join(root, "ui/event.yaml"))
snapshots = File.join(root, "ui/snapshots")

matrix = spec["matrix"]
primary = matrix["primary_locale"]
appearances = matrix["appearances"]
other_locales = matrix["locales"] - [primary]
APPEARANCE_TITLES = { "light" => "浅色", "dark" => "深色" }.freeze
LOCALE_TITLES = { "zh-Hans" => "简体中文", "en" => "English", "ja" => "日本語" }.freeze
KIND_TITLES = { "screen" => "整屏", "sheet" => "弹层", "component" => "组件" }.freeze

FileUtils.mkdir_p(File.join(out, "snapshots"))
h = ->(text) { CGI.escapeHTML(text.to_s) }

# Same name as UISnapshotCase.fileName in GeoGhostTests/UISnapshots/UISpec.swift.
file_name = ->(screen, state, appearance, locale) { "#{screen}.#{state}-#{appearance}-#{locale}.png" }

missing = []
figure = lambda do |screen, state, appearance, locale, caption|
  name = file_name.call(screen, state, appearance, locale)
  source = File.join(snapshots, name)
  unless File.exist?(source)
    missing << name
    next %(<figure class="shot missing"><div class="placeholder">还没有录制</div><figcaption>#{h.(caption)}</figcaption></figure>)
  end
  FileUtils.cp(source, File.join(out, "snapshots", name))
  %(<figure class="shot"><a href="snapshots/#{h.(name)}"><img loading="lazy" src="snapshots/#{h.(name)}" alt="#{h.(caption)}"></a><figcaption>#{h.(caption)}</figcaption></figure>)
end

events_by_screen = Hash.new { |hash, key| hash[key] = [] }
(events["events"] || {}).each { |name, event| events_by_screen[event["screen"]] << [name, event] if event["screen"] }

total_states = 0
shown_states = 0
sections = spec["screens"].map do |id, screen|
  states = screen["states"].map do |name, state|
    total_states += 1
    snapshotted = state.fetch("snapshot", true)
    shown_states += 1 if snapshotted
    is_default = name == screen["default"]
    body =
      if snapshotted
        shots = appearances.map { |a| figure.call(id, name, a, primary, "#{APPEARANCE_TITLES[a] || a} · #{LOCALE_TITLES[primary] || primary}") }
        if is_default
          shots += other_locales.map { |l| figure.call(id, name, appearances.first, l, "#{APPEARANCE_TITLES[appearances.first]} · #{LOCALE_TITLES[l] || l}") }
        end
        %(<div class="shots">#{shots.join}</div>)
      else
        %(<p class="skipped">暂时没有图：#{h.(state["reason"])}</p>)
      end
    <<~HTML
      <div class="state" id="#{h.(id)}.#{h.(name)}">
        <h3>#{h.(state["title"])} <code>#{h.(name)}</code>#{is_default ? ' <span class="tag">默认</span>' : ""}</h3>
        #{body}
      </div>
    HTML
  end

  event_list = events_by_screen[id].map do |name, event|
    properties = (event["properties"] || {}).keys
    detail = properties.empty? ? "" : %( <span class="muted">#{h.(properties.join(", "))}</span>)
    %(<li><code>#{h.(name)}</code> #{h.(event["title"])}#{detail}</li>)
  end
  events_html = event_list.empty? ? "" : %(<details class="events"><summary>这个屏幕上的事件（#{event_list.size}）</summary><ul>#{event_list.join}</ul></details>)
  unstable = (screen["unstable"] || []).map { |region| %(<p class="muted">比对时跳过一块区域：#{h.(region["reason"])}</p>) }.join
  spec_html = screen["spec"] ? %( <span class="tag">规格 #{h.(screen["spec"])}</span>) : ""

  <<~HTML
    <section id="#{h.(id)}">
      <h2>#{h.(screen["title"])} <code>#{h.(id)}</code> <span class="tag">#{h.(KIND_TITLES[screen["kind"]] || screen["kind"])}</span>#{spec_html}</h2>
      #{unstable}
      #{states.join}
      #{events_html}
    </section>
  HTML
end

nav = spec["screens"].map { |id, screen| %(<a href="##{h.(id)}">#{h.(screen["title"])}</a>) }.join
device = matrix["device"]
commit = `git -C #{root} rev-parse --short HEAD 2>/dev/null`.strip
built = Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")

html = <<~HTML
  <!doctype html>
  <html lang="zh-Hans">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GeoGhost UI 图库</title>
  <style>
    :root { color-scheme: light dark; --bg: #f6f1e7; --card: #fdfaf5; --ink: #1f1c1a; --muted: #6b665e; --rule: rgba(31,28,26,.12); --accent: #ff6b2c; }
    @media (prefers-color-scheme: dark) { :root { --bg: #171719; --card: #232326; --ink: #f2f0eb; --muted: #a6a6a6; --rule: rgba(255,255,255,.1); } }
    * { box-sizing: border-box; }
    body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.6 -apple-system, "Helvetica Neue", "PingFang SC", "Hiragino Sans", sans-serif; }
    header { padding: 32px 24px 16px; max-width: 1200px; margin: 0 auto; }
    h1 { margin: 0 0 8px; font-size: 28px; }
    header p { margin: 4px 0; color: var(--muted); }
    nav { position: sticky; top: 0; z-index: 1; background: var(--bg); border-bottom: 1px solid var(--rule); padding: 10px 24px; display: flex; gap: 6px 14px; flex-wrap: wrap; }
    nav a { color: var(--ink); text-decoration: none; font-size: 14px; }
    nav a:hover { color: var(--accent); }
    main { max-width: 1200px; margin: 0 auto; padding: 8px 24px 80px; }
    section { padding-top: 36px; }
    h2 { font-size: 22px; margin: 0 0 4px; }
    h3 { font-size: 16px; margin: 24px 0 10px; }
    code { font: 13px ui-monospace, Menlo, monospace; color: var(--muted); font-weight: normal; }
    .tag { font-size: 12px; font-weight: normal; border: 1px solid var(--rule); border-radius: 999px; padding: 1px 8px; color: var(--muted); vertical-align: middle; }
    .shots { display: flex; gap: 16px; overflow-x: auto; padding-bottom: 8px; }
    .shot { margin: 0; flex: 0 0 auto; width: 220px; }
    .shot img, .placeholder { display: block; width: 220px; border-radius: 22px; border: 1px solid var(--rule); background: var(--card); }
    .placeholder { aspect-ratio: #{device["width"]} / #{device["height"]}; display: grid; place-items: center; color: var(--muted); font-size: 14px; }
    figcaption { font-size: 13px; color: var(--muted); text-align: center; margin-top: 6px; }
    .skipped, .muted { color: var(--muted); font-size: 14px; }
    .skipped { margin: 0; }
    .events { margin-top: 20px; font-size: 14px; }
    .events summary { cursor: pointer; color: var(--muted); }
    .events li { margin: 4px 0; }
  </style>
  </head>
  <body>
  <header>
    <h1>GeoGhost UI 图库</h1>
    <p>每个屏幕、每种状态的当前样子。图片由测试自动渲染，使用固定的示例数据（图案是程序画的占位贴纸，不是真实街头作品）。点图片看原图。</p>
    <p>#{spec["screens"].size} 个屏幕，#{total_states} 种状态，其中 #{shown_states} 种有图 · #{h.(device["name"])} · 版本 #{h.(commit)} · 生成于 #{built}</p>
  </header>
  <nav>#{nav}</nav>
  <main>
  #{sections.join}
  </main>
  </body>
  </html>
HTML

File.write(File.join(out, "index.html"), html)
warn "missing snapshots: #{missing.join(", ")}" unless missing.empty?
puts "UI gallery: #{spec["screens"].size} screens, #{shown_states}/#{total_states} states with images → #{File.join(out, "index.html")}"
