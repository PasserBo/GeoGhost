#!/usr/bin/env ruby
# Builds the UI gallery: static pages showing every screen and state of ui/screen.yaml with its
# snapshot from ui/snapshots/, for people who don't open Xcode (designers, reviewers).
#
#   ruby scripts/build-ui-gallery.rb <output-dir>
#
# One page per language — index.html (简体中文, the language the lists are written in), en.html and
# ja.html — sharing the same images. Only the words around the images change; their translations
# are in ui/translations.yaml.
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
translations = YAML.load_file(File.join(root, "ui/translations.yaml"))
snapshots = File.join(root, "ui/snapshots")

matrix = spec["matrix"]
primary = matrix["primary_locale"]
appearances = matrix["appearances"]
other_locales = matrix["locales"] - [primary]
device = matrix["device"]

# The pages, in the order of the language switch. `source: true` reads titles straight from the lists.
PAGES = [
  { lang: "zh-Hans", file: "index.html", name: "简体中文", source: true },
  { lang: "en", file: "en.html", name: "English" },
  { lang: "ja", file: "ja.html", name: "日本語" },
].freeze

# The words of the page itself.
UI = {
  "zh-Hans" => {
    title: "GeoGhost UI 图库",
    intro: "每个屏幕、每种状态的当前样子。图片由测试自动渲染，使用固定的示例数据（图案是程序画的占位贴纸，不是真实街头作品）。点图片看原图。",
    summary: "%<screens>d 个屏幕，%<states>d 种状态，其中 %<shown>d 种有图 · %<device>s · 版本 %<commit>s · 生成于 %<built>s",
    screenshot_language: "截图里的界面语言见每张图下方；多数状态只截了简体中文。",
    appearance: { "light" => "浅色", "dark" => "深色" },
    kind: { "screen" => "整屏", "sheet" => "弹层", "component" => "组件" },
    default: "默认", spec: "规格", no_image: "暂时没有图：", not_recorded: "还没有录制",
    skipped: "比对时跳过一块区域：", events: "这个屏幕上的事件（%d）",
  },
  "en" => {
    title: "GeoGhost UI Gallery",
    intro: "What every screen looks like right now, in each of its states. The images are rendered automatically by tests from fixed sample data (the stickers are drawn placeholders, not real street art). Click an image to see it full size.",
    summary: "%<screens>d screens, %<states>d states, %<shown>d with an image · %<device>s · version %<commit>s · built %<built>s",
    screenshot_language: "The language of the app in each screenshot is given under it; most states are captured in Simplified Chinese only.",
    appearance: { "light" => "Light", "dark" => "Dark" },
    kind: { "screen" => "Screen", "sheet" => "Sheet", "component" => "Component" },
    default: "default", spec: "spec", no_image: "No image yet: ", not_recorded: "Not recorded yet",
    skipped: "One area is left out when comparing: ", events: "Events on this screen (%d)",
  },
  "ja" => {
    title: "GeoGhost UI ギャラリー",
    intro: "すべての画面の、それぞれの状態の現在の見た目です。画像は固定のサンプルデータからテストが自動で描画しています（ステッカーはプログラムで描いたプレースホルダーで、実際のストリートアートではありません）。画像をクリックすると原寸で表示します。",
    summary: "%<screens>d 画面、%<states>d 状態、うち %<shown>d 状態に画像あり · %<device>s · バージョン %<commit>s · 生成 %<built>s",
    screenshot_language: "スクリーンショット内のアプリの表示言語は各画像の下に記載しています。ほとんどの状態は簡体字中国語のみで撮影しています。",
    appearance: { "light" => "ライト", "dark" => "ダーク" },
    kind: { "screen" => "画面", "sheet" => "シート", "component" => "コンポーネント" },
    default: "デフォルト", spec: "仕様", no_image: "画像はまだありません：", not_recorded: "未撮影",
    skipped: "比較時に除外している領域：", events: "この画面のイベント（%d）",
  },
}.freeze

# The app language a screenshot was taken in, named the same on every page.
LOCALE_NAMES = { "zh-Hans" => "简体中文", "en" => "English", "ja" => "日本語" }.freeze

FileUtils.mkdir_p(File.join(out, "snapshots"))
h = ->(text) { CGI.escapeHTML(text.to_s) }

# Same name as UISnapshotCase.fileName in GeoGhostTests/UISnapshots/UISpec.swift.
file_name = ->(screen, state, appearance, locale) { "#{screen}.#{state}-#{appearance}-#{locale}.png" }

events_by_screen = Hash.new { |hash, key| hash[key] = [] }
(events["events"] || {}).each { |name, event| events_by_screen[event["screen"]] << [name, event] if event["screen"] }

commit = `git -C #{root} rev-parse --short HEAD 2>/dev/null`.strip
built = Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")
missing_images = []
untranslated = []

PAGES.each do |page|
  lang = page[:lang]
  ui = UI.fetch(lang)
  words = page[:source] ? nil : (translations[lang] || {})

  # Looks a translation up; on the source page, or when one is missing, the original stands.
  translate = lambda do |original, *path|
    next original if words.nil?
    found = words.dig(*path)
    untranslated << "#{lang}: #{path.join(".")}" if found.nil?
    found || original
  end
  screen_title = ->(id, screen) { translate.call(screen["title"], "screens", id, "title") }
  state_title = ->(id, name, state) { translate.call(state["title"], "screens", id, "states", name) }
  reason = ->(text) { translate.call(text, "reasons", text) }

  figure = lambda do |screen, state, appearance, locale|
    caption = "#{ui[:appearance][appearance] || appearance} · #{LOCALE_NAMES[locale] || locale}"
    name = file_name.call(screen, state, appearance, locale)
    source = File.join(snapshots, name)
    unless File.exist?(source)
      missing_images << name
      next %(<figure class="shot missing"><div class="placeholder">#{h.(ui[:not_recorded])}</div><figcaption>#{h.(caption)}</figcaption></figure>)
    end
    FileUtils.cp(source, File.join(out, "snapshots", name))
    %(<figure class="shot"><a href="snapshots/#{h.(name)}"><img loading="lazy" src="snapshots/#{h.(name)}" alt="#{h.(caption)}"></a><figcaption>#{h.(caption)}</figcaption></figure>)
  end

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
          shots = appearances.map { |a| figure.call(id, name, a, primary) }
          shots += other_locales.map { |l| figure.call(id, name, appearances.first, l) } if is_default
          %(<div class="shots">#{shots.join}</div>)
        else
          %(<p class="skipped">#{h.(ui[:no_image])}#{h.(reason.call(state["reason"]))}</p>)
        end
      <<~HTML
        <div class="state" id="#{h.(id)}.#{h.(name)}">
          <h3>#{h.(state_title.call(id, name, state))} <code>#{h.(name)}</code>#{is_default ? %( <span class="tag">#{h.(ui[:default])}</span>) : ""}</h3>
          #{body}
        </div>
      HTML
    end

    event_list = events_by_screen[id].map do |name, event|
      properties = (event["properties"] || {}).keys
      detail = properties.empty? ? "" : %( <span class="muted">#{h.(properties.join(", "))}</span>)
      %(<li><code>#{h.(name)}</code> #{h.(translate.call(event["title"], "events", name))}#{detail}</li>)
    end
    events_html = event_list.empty? ? "" : %(<details class="events"><summary>#{h.(format(ui[:events], event_list.size))}</summary><ul>#{event_list.join}</ul></details>)
    unstable = (screen["unstable"] || []).map { |region| %(<p class="muted">#{h.(ui[:skipped])}#{h.(reason.call(region["reason"]))}</p>) }.join
    spec_html = screen["spec"] ? %( <span class="tag">#{h.(ui[:spec])} #{h.(screen["spec"])}</span>) : ""

    <<~HTML
      <section id="#{h.(id)}">
        <h2>#{h.(screen_title.call(id, screen))} <code>#{h.(id)}</code> <span class="tag">#{h.(ui[:kind][screen["kind"]] || screen["kind"])}</span>#{spec_html}</h2>
        #{unstable}
        #{states.join}
        #{events_html}
      </section>
    HTML
  end

  nav = spec["screens"].map { |id, screen| %(<a href="##{h.(id)}">#{h.(screen_title.call(id, screen))}</a>) }.join
  switch = PAGES.map do |other|
    other[:lang] == lang ? %(<strong>#{h.(other[:name])}</strong>) : %(<a href="#{other[:file]}" data-lang="#{other[:lang]}">#{h.(other[:name])}</a>)
  end.join(" · ")
  summary = format(ui[:summary], screens: spec["screens"].size, states: total_states, shown: shown_states,
                                 device: device["name"], commit: commit, built: built)

  # A first visit to the Chinese page goes to the reader's own language when there is a page for
  # it; choosing a language in the switch is remembered and wins from then on.
  redirect = page[:source] ? <<~JS : ""
    var saved = null;
    try { saved = localStorage.getItem("ui-gallery-lang"); } catch (e) {}
    var wanted = saved || ((navigator.language || "").toLowerCase().indexOf("ja") === 0 ? "ja"
      : (navigator.language || "").toLowerCase().indexOf("zh") === 0 ? "zh-Hans" : "en");
    var pages = { en: "en.html", ja: "ja.html" };
    if (pages[wanted]) location.replace(pages[wanted] + location.hash);
  JS

  html = <<~HTML
    <!doctype html>
    <html lang="#{lang}">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#{h.(ui[:title])}</title>
    <script>
    #{redirect}
    document.addEventListener("click", function (event) {
      var link = event.target.closest && event.target.closest("a[data-lang]");
      if (link) { try { localStorage.setItem("ui-gallery-lang", link.getAttribute("data-lang")); } catch (e) {} }
    });
    </script>
    <style>
      :root { color-scheme: light dark; --bg: #f6f1e7; --card: #fdfaf5; --ink: #1f1c1a; --muted: #6b665e; --rule: rgba(31,28,26,.12); --accent: #ff6b2c; }
      @media (prefers-color-scheme: dark) { :root { --bg: #171719; --card: #232326; --ink: #f2f0eb; --muted: #a6a6a6; --rule: rgba(255,255,255,.1); } }
      * { box-sizing: border-box; }
      body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.6 -apple-system, "Helvetica Neue", "PingFang SC", "Hiragino Sans", sans-serif; }
      header { padding: 32px 24px 16px; max-width: 1200px; margin: 0 auto; }
      h1 { margin: 0 0 8px; font-size: 28px; }
      header p { margin: 4px 0; color: var(--muted); }
      .languages { float: right; font-size: 14px; color: var(--muted); padding-top: 10px; }
      .languages a { color: var(--accent); text-decoration: none; }
      .languages strong { color: var(--ink); }
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
      <div class="languages">#{switch}</div>
      <h1>#{h.(ui[:title])}</h1>
      <p>#{h.(ui[:intro])}</p>
      <p>#{h.(ui[:screenshot_language])}</p>
      <p>#{h.(summary)}</p>
    </header>
    <nav>#{nav}</nav>
    <main>
    #{sections.join}
    </main>
    </body>
    </html>
  HTML

  File.write(File.join(out, page[:file]), html)
  puts "UI gallery (#{lang}): #{spec["screens"].size} screens, #{shown_states}/#{total_states} states with images → #{File.join(out, page[:file])}" if page[:source]
end

warn "missing snapshots: #{missing_images.uniq.join(", ")}" unless missing_images.empty?
# A page with a Chinese title in the middle of English is still usable, so this warns rather than
# fails the docs build; the tests are what keep ui/translations.yaml complete.
warn "untranslated (shown in Chinese): #{untranslated.uniq.join(", ")}" unless untranslated.empty?
