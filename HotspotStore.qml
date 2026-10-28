pragma Singleton

import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The hotspot folder, and the shared popup that shows it.
//
// A singleton because a bar widget is instantiated once per monitor; one
// store means one popup and one folder watcher however many bars there are.
//
// A normal folder is read by FolderListModel. One too large to watch is read
// by bin/hotspot instead, polled, so a folder that keeps changing costs one
// scan per interval rather than one per file. The helper gets an argument
// array, never a shell string, and refuses anything but an absolute directory.
//
// Filenames are chosen by whoever made the file, so every Text is PlainText,
// and every exec is an argument array: Util.execDetached runs its string
// through `bash -lc`, and a file named `; rm -rf ~` would be a command.
//
// Adapted from jankeesvw/omarchy-downloads (MIT).
Singleton {
  id: root

  readonly property string homePath:
    String(StandardPaths.writableLocation(StandardPaths.HomeLocation)).replace(/^file:\/\//, "")

  // The folder the panel always opens on, and the one shown right now - a
  // pinned folder can take over until the panel closes.
  //
  // The home folder is the `folder` setting when one is set. Otherwise it
  // follows the first-run question (bin/hotspot firstrun): Desktop if the
  // user agreed to set one up, Downloads if they declined or have not
  // answered. Nothing is created or bookmarked without that answer.
  property string folderSetting: ""
  property string setupChoice: ""
  property string downloadDir: root.homePath + "/Downloads"
  readonly property string homeFolder: root.folderSetting !== "" ? root.folderSetting
    : (root.setupChoice === "desktop" ? root.homePath + "/Desktop" : root.downloadDir)
  property string folderPath: root.homeFolder

  onHomeFolderChanged: {
    if (!root.open) root.folderPath = root.homeFolder
    root.parseUserDirs(root.lastUserDirs)
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (root.homePath + "/.local/state")) + "/faux-desktop/setup"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.setupChoice = String(text()).trim()
    onLoadFailed: root.setupChoice = ""
  }
  property string sortBy: "newest"
  property string dropAction: "copied"
  // Panel size in px, set by dragging the bottom-right corner and kept in the
  // bar entry (panelWidth / panelHeight).
  property int panelWidth: 1040
  property int panelHeight: 600

  function savePanelSize(w, h) {
    root.panelWidth = Math.round(w)
    root.panelHeight = Math.round(h)
    // One process for both writes: two parallel `bar set`s would race on
    // shell.json. Values go in as arguments, never into the script text.
    Quickshell.execDetached(["sh", "-c",
      'omarchy bar set crispin81.faux-desktop panelWidth "$1" && omarchy bar set crispin81.faux-desktop panelHeight "$2"',
      "sh", String(root.panelWidth), String(root.panelHeight)])
  }

  // "list" or "icons"; picked in the panel header and kept in the bar entry.
  property string viewMode: "list"

  function setViewMode(v) {
    if ((v !== "list" && v !== "icons") || v === root.viewMode) return
    root.viewMode = v
    Quickshell.execDetached(["omarchy", "bar", "set", "crispin81.faux-desktop", "viewMode", v])
  }

  readonly property url folderUrl: root.fileUrl(root.folderPath)

  function plain(s) { return String(s || "").replace(/[<>]/g, "") }

  function displayOf(path) {
    var home = root.homePath
    if (home !== "" && (path === home || path.indexOf(home + "/") === 0)) return "~" + path.slice(home.length)
    return path
  }
  readonly property string displayPath: root.displayOf(root.folderPath)

  // Pinned folders: the standard user folders, read from user-dirs.dirs so
  // a renamed Downloads still lands right. The home folder (the `folder`
  // setting, Desktop by default) always comes first.
  property var pinned: []
  property string lastUserDirs: ""

  function parseUserDirs(text) {
    root.lastUserDirs = String(text || "")
    var dirs = {}
    var lines = root.lastUserDirs.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = /^XDG_([A-Z]+)_DIR="(.*)"\s*$/.exec(lines[i].trim())
      if (m) dirs[m[1]] = m[2].replace(/^\$HOME/, root.homePath).replace(/\/+$/, "")
    }
    if (dirs.DOWNLOAD && dirs.DOWNLOAD !== root.homePath) root.downloadDir = dirs.DOWNLOAD
    var wanted = [["DOWNLOAD", "Downloads"], ["DOCUMENTS", "Documents"], ["PICTURES", "Pictures"], ["VIDEOS", "Videos"]]
    var out = [{ label: root.labelOf(root.homeFolder), path: root.homeFolder }]
    for (var k = 0; k < wanted.length; k++) {
      var path = dirs[wanted[k][0]] || (root.homePath + "/" + wanted[k][1])
      // An unset folder is spelled as $HOME itself; skip it rather than show home.
      if (path === root.homePath || path === root.homeFolder || path.charAt(0) !== "/") continue
      out.push({ label: root.labelOf(path), path: path })
    }
    root.pinned = out
  }

  function labelOf(path) {
    var name = String(path).replace(/\/+$/, "").replace(/^.*\//, "")
    return name !== "" ? name : "/"
  }

  // Show a folder for now; the panel goes back to homeFolder when it closes.
  function switchTo(path) {
    if (path.length < 2 || path.charAt(0) !== "/" || path === root.folderPath) return
    root.folderPath = path
    // Read while the pointer was resting, so the list changes on the second
    // itself rather than after a folder read. The watcher catches up after.
    if (root.preloadPath === path && root.preloadText !== "") root.applyPayload(root.preloadText)
  }

  // The pinned folder the current one lives under (or is), if any.
  readonly property var pinnedRoot: {
    for (var i = 0; i < root.pinned.length; i++) {
      var p = root.pinned[i].path
      if (root.folderPath === p || root.folderPath.indexOf(p + "/") === 0) return root.pinned[i]
    }
    return null
  }
  // Below a pinned folder: the back button has somewhere to go.
  readonly property bool canGoUp: root.pinnedRoot !== null && root.folderPath !== root.pinnedRoot.path

  // "Desktop / Clients / 2026" under a pinned folder, else the plain path.
  readonly property var crumbs: {
    if (!root.pinnedRoot || root.folderPath === root.pinnedRoot.path) return []
    return root.folderPath.slice(root.pinnedRoot.path.length + 1).split("/")
  }

  function enterFolder(path) { root.switchTo(path) }

  function goUp() {
    if (!root.canGoUp) return
    root.switchTo(root.folderPath.replace(/\/[^\/]+$/, ""))
  }

  property string preloadPath: ""
  property string preloadText: ""
  function preload(path) {
    if (root.preloadPath === path && (preProc.running || root.preloadText !== "")) return
    root.preloadPath = path
    root.preloadText = ""
    if (preProc.running) preProc.running = false
    preProc.command = [root.helper, "list", path]
    preProc.running = true
  }

  // Resting on a pinned folder for a quarter second switches to it.
  property string pendingPath: ""
  function hoverPinned(path) {
    if (path === root.folderPath) return
    root.pendingPath = path
    dwell.restart()
    root.preload(path)
  }
  function leavePinned(path) { if (root.pendingPath === path) { root.pendingPath = ""; dwell.stop() } }

  Timer {
    id: dwell
    interval: 250
    onTriggered: { if (root.pendingPath !== "") root.switchTo(root.pendingPath); root.pendingPath = "" }
  }

  FileView {
    path: root.homePath + "/.config/user-dirs.dirs"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parseUserDirs(text())
    onLoadFailed: root.parseUserDirs("")
  }

  readonly property string iconHotspot: ""
  readonly property string iconFolder: ""
  readonly property string iconFile: ""
  readonly property string iconImage: ""
  readonly property string iconPdf: ""
  readonly property string iconArchive: ""
  readonly property string iconAudio: ""
  readonly property string iconVideo: ""
  readonly property string iconCode: ""
  readonly property string iconText: ""
  readonly property string iconAdd: ""

  property string fontFamily: Style.font.family

  // Rows currently shown, already sorted and capped.
  property var files: []
  property int totalCount: 0
  property int hiddenCount: 0
  property int uncountedCount: 0
  property double now: Date.now()
  property string draggingUrl: ""
  property bool open: false
  // Something from outside is being dragged over the card right now.
  property bool receiving: false
  // Last add that failed, shown under the list until the next one.
  property string addError: ""


  readonly property int maxRows: 200
  readonly property int maxScan: 2000

  property bool polling: false
  property url scanFolder: ""

  function expandPath(p) {
    var s = String(p || "").trim()
    if (s === "~") return root.homePath
    if (s.indexOf("~/") === 0) return root.homePath + s.slice(1)
    return s.replace(/\/+$/, "")
  }

  function configure(opts) {
    // Empty means "follow the first-run choice". Absolute only otherwise: a
    // relative or dash-led path never reaches a command.
    var path = opts.folder ? root.expandPath(opts.folder) : ""
    root.folderSetting = (path.length > 1 && path.charAt(0) === "/") ? path : ""
    if (opts.sortBy === "name" || opts.sortBy === "newest") root.sortBy = opts.sortBy
    if (opts.dropAction === "moved" || opts.dropAction === "copied") root.dropAction = opts.dropAction
    if (opts.viewMode === "list" || opts.viewMode === "icons") root.viewMode = opts.viewMode
    var pw = Number(opts.panelWidth), ph = Number(opts.panelHeight)
    if (isFinite(pw) && pw >= 360 && pw <= 8000) root.panelWidth = Math.round(pw)
    if (isFinite(ph) && ph >= 240 && ph <= 8000) root.panelHeight = Math.round(ph)
  }

  function hide() { root.open = false; root.pendingPath = ""; dwell.stop() }

  // Every opening settles on the home folder.
  onOpenChanged: if (!root.open && root.draggingUrl === "") root.folderPath = root.homeFolder

  function showOn(anchor, bar, owner, byHover) {
    root.rescan()
    if (anchor) {
      win.anchorItem = anchor
      win.bar = bar
      win.owner = owner
    }
    win.autoClose = !!byHover
    root.addError = ""
    root.folderPath = root.homeFolder
    root.open = true
  }

  function suffixOf(name) {
    var m = /\.([A-Za-z0-9]+)$/.exec(String(name))
    return m ? m[1].toLowerCase() : ""
  }

  function isImage(name) {
    return /^(png|jpg|jpeg|gif|webp|bmp|svg|avif|ico|tiff?)$/.test(root.suffixOf(name))
  }

  function iconFor(name, isDir) {
    if (isDir) return root.iconFolder
    var s = root.suffixOf(name)
    if (/^(png|jpg|jpeg|gif|webp|bmp|svg|avif|heic|ico|tiff?|cr2|cr3|nef|arw|dng|raf|orf)$/.test(s)) return root.iconImage
    if (s === "pdf") return root.iconPdf
    if (/^(zip|tar|gz|tgz|bz2|xz|7z|rar|zst|deb|rpm|pkg|iso|img|dmg|appimage)$/.test(s)) return root.iconArchive
    if (/^(mp3|wav|flac|ogg|m4a|aac|opus|wma)$/.test(s)) return root.iconAudio
    if (/^(mp4|mkv|mov|avi|webm|m4v|mpg|mpeg|wmv)$/.test(s)) return root.iconVideo
    if (/^(js|ts|json|py|rb|sh|c|h|cpp|rs|go|java|qml|html|css|xml|yml|yaml|toml)$/.test(s)) return root.iconCode
    if (/^(txt|md|csv|log|rtf|doc|docx|odt|xls|xlsx|ods|ppt|pptx|odp|epub)$/.test(s)) return root.iconText
    return root.iconFile
  }

  function formatSize(bytes) {
    var n = Number(bytes)
    if (!isFinite(n) || n < 0) return ""
    if (n < 1024) return n + " B"
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB"
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(n < 10 * 1024 * 1024 ? 1 : 0) + " MB"
    return (n / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function formatAge(ms) {
    var secs = Math.max(0, Math.round((root.now - ms) / 1000))
    if (secs < 45) return "just now"
    var mins = Math.round(secs / 60)
    if (mins < 60) return mins + " min"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return hours + " h"
    var days = Math.floor(hours / 24)
    if (days < 7) return days + " d"
    var weeks = Math.floor(days / 7)
    if (weeks < 5) return weeks + " w"
    return Math.floor(days / 30) + " mo"
  }

  // Folders first, then by the chosen order. The model already sorts, but the
  // helper route always comes back newest first, so both are sorted here.
  function sortRows(rows) {
    rows.sort(function(a, b) {
      if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
      if (root.sortBy === "name")
        return a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" })
      return b.modified - a.modified
    })
    return rows
  }

  function publish(rows, uncounted) {
    root.sortRows(rows)
    root.totalCount = rows.length
    root.hiddenCount = Math.max(0, rows.length - root.maxRows)
    root.files = rows.slice(0, root.maxRows)
    root.uncountedCount = uncounted
  }

  function rebuild() {
    var rows = []
    var count = folderModel.count
    var scan = Math.min(count, root.maxScan)
    for (var i = 0; i < scan; i++) {
      var name = String(folderModel.get(i, "fileName") || "")
      if (name === "") continue
      var mod = folderModel.get(i, "fileModified")
      rows.push({
        name: name,
        url: String(folderModel.get(i, "fileUrl") || ""),
        path: String(folderModel.get(i, "filePath") || ""),
        size: Number(folderModel.get(i, "fileSize")) || 0,
        isDir: !!folderModel.get(i, "fileIsDir"),
        modified: mod ? mod.getTime() : 0
      })
    }
    root.publish(rows, count - scan)
  }

  function tick() {
    root.now = Date.now()
    if (root.polling) { root.readViaHelper(); return }
    if (String(root.scanFolder) === "" || folderModel.status !== FolderListModel.Ready) return
    root.rebuild()
    if (folderModel.count > root.maxScan) {
      root.polling = true
      root.scanFolder = ""
      root.readViaHelper()
    }
  }

  // Ask the folder's size before the model is ever attached: FolderListModel
  // walks and stats the whole directory on the UI thread before a count exists.
  function rescan() {
    if (probeProc.running) return
    probeProc.command = [root.helper, "probe", root.folderPath]
    probeProc.running = true
  }

  function applyProbe(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { return }
    if (!data || data.ok !== true) {
      root.files = []
      root.totalCount = 0
      return
    }
    if (data.over === true) {
      root.polling = true
      if (String(root.scanFolder) !== "") root.scanFolder = ""
      root.readViaHelper()
      return
    }
    root.polling = false
    if (String(root.scanFolder) === "") root.scanFolder = root.folderUrl
    else root.tick()
  }

  function readViaHelper() {
    if (listProc.running) return
    listProc.command = [root.helper, "list", root.folderPath]
    listProc.running = true
  }

  // Percent-encode per segment, so a name carrying a newline cannot split one
  // text/uri-list entry into two.
  function fileUrl(path) {
    var parts = String(path || "").split("/")
    for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
    return "file://" + parts.join("/")
  }

  function applyPayload(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { return }
    if (!data || data.ok !== true || !Array.isArray(data.files)) return
    var rows = []
    for (var i = 0; i < data.files.length; i++) {
      var f = data.files[i]
      var name = String(f.name || "")
      if (name === "") continue
      rows.push({
        name: name,
        url: root.fileUrl(f.path),
        path: String(f.path || ""),
        size: Number(f.size) || 0,
        isDir: f.isDir === true,
        modified: Number(f.modified) || 0
      })
    }
    root.publish(rows, Number(data.hidden) || 0)
  }

  function scheduleTick() { coalesce.restart() }

  // Ask the first-run question if it has never been asked. The helper exits
  // at once when it has, so this is cheap on every start.
  function firstRun() {
    Quickshell.execDetached([root.helper, "firstrun"])
  }

  function openFolder() {
    var target = root.folderPath
    if (target.length > 1 && target.charAt(0) === "/")
      Quickshell.execDetached(["xdg-open", target])
  }

  function openFile(path) {
    var target = String(path || "")
    if (target.length > 1 && target.charAt(0) === "/")
      Quickshell.execDetached(["xdg-open", target])
  }

  // Dropped files land in the folder. Local files only (file:// URLs), never
  // overwriting anything already there, and never a file onto itself.
  function addFiles(urls) { root.addFilesTo(urls, root.folderPath) }

  // Copy (or move, per the dropAction setting) dropped files into `dir`.
  function addFilesTo(urls, dir) {
    if (String(dir).length < 2 || String(dir).charAt(0) !== "/") return
    var paths = []
    for (var i = 0; i < urls.length; i++) {
      var u = String(urls[i])
      if (u.indexOf("file://") !== 0) continue
      var p
      try { p = decodeURIComponent(u.slice(7)) } catch (e) { continue }
      if (p.length < 2 || p.charAt(0) !== "/") continue
      var parent = p.replace(/\/+$/, "").replace(/\/[^\/]*$/, "")
      if (parent === dir || p === dir) continue
      paths.push(p)
    }
    if (paths.length === 0) return
    root.addError = ""
    var cmd = root.dropAction === "moved"
      ? ["mv", "--no-clobber", "--"]
      : ["cp", "-r", "--preserve=timestamps", "--update=none", "--"]
    addProc.command = cmd.concat(paths, [dir + "/"])
    addProc.running = true
  }

  // A file dragged from this panel onto one of its folders moves in, as in a
  // file manager. Never into itself or below itself.
  property bool internalDrop: false
  function moveInto(url, dir) {
    var p
    try { p = decodeURIComponent(String(url).replace(/^file:\/\//, "")) } catch (e) { return }
    if (p.length < 2 || p.charAt(0) !== "/" || dir === p || dir.indexOf(p + "/") === 0) return
    root.internalDrop = true
    root.addError = ""
    addProc.command = ["mv", "--no-clobber", "--", p, dir + "/"]
    addProc.running = true
  }

  // Spring-loaded folders: hold dragged files over a folder and it opens.
  // Only for drags from outside - swapping the list under a drag that started
  // in this panel would destroy the item the drag belongs to.
  property string springPath: ""
  // Wait before a held drag opens a folder (or goes up, on the back button).
  readonly property int springDelay: 400
  function springHover(path) {
    if (root.draggingUrl !== "") return
    root.springPath = path
    springTimer.restart()
    if (path !== "..") root.preload(path)
  }
  function springLeave(path) {
    if (root.springPath === path) { root.springPath = ""; springTimer.stop() }
  }
  Timer {
    id: springTimer
    interval: root.springDelay
    onTriggered: {
      var p = root.springPath
      root.springPath = ""
      if (p === "..") root.goUp()
      else if (p !== "") root.enterFolder(p)
    }
  }

  onFolderPathChanged: {
    root.polling = false
    root.scanFolder = ""
    root.files = []
    root.rescan()
  }
  onSortByChanged: root.tick()

  Timer {
    id: coalesce
    interval: 250
    repeat: false
    onTriggered: root.tick()
  }

  readonly property string helper:
    Qt.resolvedUrl("bin/hotspot").toString().replace(/^file:\/\//, "")

  Component.onCompleted: { root.firstRun(); root.rescan() }

  Process {
    id: probeProc
    stdout: StdioCollector { onStreamFinished: root.applyProbe(text) }
  }

  Process {
    id: listProc
    stdout: StdioCollector { onStreamFinished: root.applyPayload(text) }
  }

  Process {
    id: preProc
    property string forPath: ""
    onStarted: forPath = root.preloadPath
    stdout: StdioCollector {
      onStreamFinished: if (preProc.forPath === root.preloadPath) {
        root.preloadText = text
        if (root.folderPath === root.preloadPath && root.files.length === 0) root.applyPayload(text)
      }
    }
  }

  Process {
    id: addProc
    stderr: StdioCollector {
      onStreamFinished: if (String(text).trim() !== "") root.addError = String(text).trim().split("\n")[0]
    }
    onExited: root.rescan()
  }

  FolderListModel {
    id: folderModel
    folder: root.scanFolder
    showDirs: true
    showDirsFirst: true
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Time
    onCountChanged: root.scheduleTick()
    // A fresh folder is drawn at once; only bursts of changes are coalesced.
    onStatusChanged: if (status === FolderListModel.Ready) root.tick()
  }

  Timer {
    interval: root.open ? 20000 : 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.rescan()
  }

  HotspotPopup {
    id: win

    open: root.open
    dragging: root.draggingUrl !== ""
    receiving: root.receiving
    // Sized by the corner grip and remembered; the popup clamps it to the screen.
    contentWidth: root.panelWidth
    contentHeight: root.panelHeight
    onResizing: function(w, h) { root.panelWidth = Math.round(w); root.panelHeight = Math.round(h) }
    onResized: function(w, h) { root.savePanelSize(w, h) }

    onDismissed: root.hide()
    onWandered: root.hide()

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.hide()

      // Anything dragged in from another window lands in the folder.
      DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: function(drag) {
          // Our own rows are dragged from here too; dropping one back is a no-op.
          if (root.draggingUrl !== "") { drag.accepted = false; return }
          root.receiving = true
          drag.accept(Qt.CopyAction)
        }
        onExited: root.receiving = false
        onDropped: function(d) {
          root.receiving = false
          if (d.hasUrls) {
            root.addFiles(d.urls)
            d.accept(Qt.CopyAction)
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          // Up one level, while inside a subfolder of a pinned folder. Files
          // held over it spring up a level, like folders spring open.
          Button {
            id: backButton
            Layout.alignment: Qt.AlignVCenter
            iconText: "\uF060"
            tooltipText: root.canGoUp ? "Back" : ""
            enabled: root.canGoUp
            opacity: root.canGoUp ? 1 : 0.35
            bordered: true
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.fontFamily
            iconSize: Style.font.iconSmall
            onClicked: root.goUp()

            readonly property bool springing: root.springPath === ".."
            property real springProgress: 0
            onSpringingChanged: {
              backSweep.stop()
              backButton.springProgress = 0
              if (backButton.springing) backSweep.start()
            }
            NumberAnimation {
              id: backSweep
              target: backButton
              property: "springProgress"
              from: 0
              to: 1
              duration: root.springDelay
            }

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * backButton.springProgress
              radius: Style.space(4)
              color: Util.alpha(Commons.Color.accent, 0.30)
            }

            DropArea {
              anchors.fill: parent
              keys: ["text/uri-list"]
              onEntered: function(drag) {
                if (!root.canGoUp || root.draggingUrl !== "") { drag.accepted = false; return }
                root.springHover("..")
                drag.accept(Qt.CopyAction)
              }
              onExited: root.springLeave("..")
              onDropped: function(d) {
                // Dropping on it puts the files one level up.
                root.springLeave("..")
                root.receiving = false
                if (d.hasUrls && root.canGoUp) {
                  root.addFilesTo(d.urls, root.folderPath.replace(/\/[^\/]+$/, ""))
                  d.accept(Qt.CopyAction)
                }
              }
            }
          }

          // Pinned folders, top left. Rest on one for a second (or click it)
          // to show it; every opening starts back on the first one.
          Flow {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.space(6)

            Repeater {
              model: root.pinned
              delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool current: root.pinnedRoot !== null && modelData.path === root.pinnedRoot.path
                readonly property bool pending: modelData.path === root.pendingPath
                height: Style.space(30)
                width: chipLabel.implicitWidth + Style.space(22)
                radius: Style.space(6)
                color: chip.current ? Util.alpha(Commons.Color.accent, 0.22)
                  : (chipMouse.containsMouse || chipDrop.containsDrag ? Util.alpha(Commons.Color.foreground, 0.12)
                  : Util.alpha(Commons.Color.foreground, 0.06))
                border.width: chip.current ? Math.max(1, Style.spacing.hairline) : 0
                border.color: Commons.Color.accent
                clip: true

                // Sweeps left to right over the dwell quarter-second, so the wait is
                // visible and the switch lands as the sweep reaches the end.
                property real progress: 0
                onPendingChanged: {
                  sweep.stop()
                  chip.progress = 0
                  if (chip.pending) sweep.start()
                }
                NumberAnimation {
                  id: sweep
                  target: chip
                  property: "progress"
                  from: 0
                  to: 1
                  duration: 250
                }
                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width * chip.progress
                  radius: chip.radius
                  color: Util.alpha(Commons.Color.accent, 0.30)
                }

                Text {
                  id: chipLabel
                  anchors.centerIn: parent
                  text: modelData.label
                  textFormat: Text.PlainText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  renderType: Text.NativeRendering
                  color: chip.current ? Commons.Color.accent : Commons.Color.foreground
                }

                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.hoverPinned(modelData.path)
                  onExited: root.leavePinned(modelData.path)
                  onClicked: { root.leavePinned(modelData.path); root.switchTo(modelData.path) }
                }

                // Holding dragged files on a folder switches to it as well.
                DropArea {
                  id: chipDrop
                  anchors.fill: parent
                  keys: ["text/uri-list"]
                  onEntered: function(drag) {
                    // A drag from inside the panel must not swap the list under it.
                    if (root.draggingUrl !== "") { drag.accepted = false; return }
                    root.hoverPinned(modelData.path)
                    drag.accept(Qt.CopyAction)
                  }
                  onExited: root.leavePinned(modelData.path)
                  onDropped: function(d) {
                    root.leavePinned(modelData.path)
                    root.receiving = false
                    if (d.hasUrls && root.draggingUrl === "") {
                      root.switchTo(modelData.path)
                      root.addFiles(d.urls)
                      d.accept(Qt.CopyAction)
                    }
                  }
                }
              }
            }

            // Where you are below the pinned folder: "/ Clients / 2026".
            Text {
              visible: root.crumbs.length > 0
              height: Style.space(30)
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(4)
              text: "/ " + root.crumbs.join(" / ")
              textFormat: Text.PlainText
              elide: Text.ElideLeft
              width: Math.min(implicitWidth, Style.space(420))
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              color: Commons.Color.accent
            }
          }


          ButtonGroup {
            Layout.alignment: Qt.AlignVCenter
            options: [
              { value: "newest", label: "Newest" },
              { value: "name", label: "A–Z" }
            ]
            value: root.sortBy
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.sortBy = v }
          }

          ButtonGroup {
            Layout.alignment: Qt.AlignVCenter
            options: [
              { value: "list", label: "", icon: "\uF03A", tooltip: "List view" },
              { value: "icons", label: "", icon: "\uF00A", tooltip: "Icon view" }
            ]
            value: root.viewMode
            foreground: Commons.Color.foreground
            accent: Commons.Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            focusable: false
            onChanged: function(v) { root.setViewMode(v) }
          }

        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          color: Commons.Color.menu.border
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: 0

          ListView {
            id: list
            anchors.fill: parent
            visible: root.files.length > 0 && root.viewMode === "list"
            clip: true
            spacing: Style.space(2)
            model: root.files
            boundsBehavior: Flickable.StopAtBounds
            QQC.ScrollBar.vertical: QQC.ScrollBar {
              // Shown whenever the files overflow, not only mid-scroll.
              policy: parent.contentHeight > parent.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
              width: Style.space(10)
              contentItem: Rectangle {
                implicitWidth: Style.space(6)
                radius: width / 2
                color: Util.alpha(Commons.Color.accent, parent.pressed ? 0.8 : (parent.hovered ? 0.6 : 0.4))
              }
              background: Rectangle {
                radius: width / 2
                color: Util.alpha(Commons.Color.foreground, 0.06)
              }
            }

            delegate: FileRow {
              required property var modelData
              // Leave a lane for the scrollbar.
              width: list.width - Style.space(14)
              store: root
              file: modelData || ({})
            }
          }

          GridView {
            id: grid
            anchors.fill: parent
            visible: root.files.length > 0 && root.viewMode === "icons"
            clip: true
            model: root.viewMode === "icons" ? root.files : []
            boundsBehavior: Flickable.StopAtBounds
            QQC.ScrollBar.vertical: QQC.ScrollBar {
              // Shown whenever the files overflow, not only mid-scroll.
              policy: parent.contentHeight > parent.height ? QQC.ScrollBar.AlwaysOn : QQC.ScrollBar.AlwaysOff
              width: Style.space(10)
              contentItem: Rectangle {
                implicitWidth: Style.space(6)
                radius: width / 2
                color: Util.alpha(Commons.Color.accent, parent.pressed ? 0.8 : (parent.hovered ? 0.6 : 0.4))
              }
              background: Rectangle {
                radius: width / 2
                color: Util.alpha(Commons.Color.foreground, 0.06)
              }
            }
            // As many columns as fit at roughly 130px, stretched to fill the row.
            readonly property int columns: Math.max(1, Math.floor((width - Style.space(14)) / Style.space(130)))
            cellWidth: Math.floor((width - Style.space(14)) / columns)
            cellHeight: Math.round(cellWidth * 0.75) + Style.space(48)

            delegate: FileTile {
              required property var modelData
              width: grid.cellWidth
              height: grid.cellHeight
              store: root
              file: modelData || ({})
            }
          }

          Text {
            anchors.fill: parent
            visible: root.files.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.displayPath + " is empty.\nDrop files here to add them."
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
            color: Commons.Color.muted
          }

          // Drop highlight over the whole list while something is held over it.
          Rectangle {
            anchors.fill: parent
            visible: root.receiving
            radius: Style.space(6)
            color: Util.alpha(Commons.Color.accent, 0.12)
            border.width: Math.max(1, Style.space(2))
            border.color: Commons.Color.accent

            Text {
              anchors.centerIn: parent
              text: root.iconAdd + "  " + (root.dropAction === "moved" ? "Move" : "Copy") + " to " + root.displayPath
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.NativeRendering
              color: Commons.Color.accent
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.addError !== ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: root.addError
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Commons.Color.urgent
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: (root.uncountedCount > 0 || root.hiddenCount > 0
                  ? "Showing " + root.files.length + " of " + (root.uncountedCount > 0 ? "more than " + root.maxScan : root.totalCount) + ".  "
                  : "")
                + "Drag out to use · drop in to add · click a folder to go in · double-click a file to open"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          renderType: Text.NativeRendering
          color: Commons.Color.muted
        }
      }
    }
  }
}
