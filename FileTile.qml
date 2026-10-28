import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// One file in the icon view: a thumbnail (or a big type glyph) over its name.
// Drags exactly like FileRow - a real Wayland drag carrying text/uri-list.
Item {
  id: tile

  property var store: null
  // { name, url, path, size, isDir, modified }
  property var file: ({})

  readonly property bool dragging: store !== null && !!file && store.draggingUrl === file.url
  readonly property bool image: !!(store && file && !file.isDir && store.isImage(file.name))

  Drag.active: tileDrag.active
  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction
  Drag.mimeData: ({
    "text/uri-list": String(tile.file.url || "") + "\r\n",
    "text/plain": String(tile.file.url || "")
  })
  Drag.onDragStarted: if (tile.store) tile.store.draggingUrl = String(tile.file.url || "")
  // Close on every finished drag, as FileRow does: Wayland reports
  // IgnoreAction even for accepted drops, and an open popup would swallow
  // the next click in the app you dropped into.
  Drag.onDragFinished: {
    if (!tile.store) return
    tile.store.draggingUrl = ""
    // Dropped onto one of the panel's own folders: stay open to see it land.
    if (!tile.store.internalDrop) tile.store.open = false
    tile.store.internalDrop = false
  }

  // Folders are drop targets: files from outside spring the folder open after
  // a moment (or land in it on drop); files from this panel move into it.
  readonly property bool springing: !!(store && file && file.isDir && store.springPath === file.path)
  property real springProgress: 0
  onSpringingChanged: {
    springSweep.stop()
    tile.springProgress = 0
    if (tile.springing) springSweep.start()
  }
  NumberAnimation {
    id: springSweep
    target: tile
    property: "springProgress"
    from: 0
    to: 1
    duration: store ? store.springDelay : 400
  }

  DropArea {
    id: folderDrop
    anchors.fill: parent
    enabled: !!(tile.file && tile.file.isDir)
    keys: ["text/uri-list"]
    onEntered: function(drag) {
      if (!tile.store) { drag.accepted = false; return }
      if (tile.store.draggingUrl !== "") {
        // From this panel: no dropping a folder onto itself.
        if (tile.store.draggingUrl === String(tile.file.url || "")) { drag.accepted = false; return }
        drag.accept(Qt.MoveAction)
        return
      }
      tile.store.springHover(String(tile.file.path || ""))
      drag.accept(Qt.CopyAction)
    }
    onExited: if (tile.store) tile.store.springLeave(String(tile.file.path || ""))
    onDropped: function(d) {
      if (!tile.store) return
      var dir = String(tile.file.path || "")
      tile.store.springLeave(dir)
      if (tile.store.draggingUrl !== "") {
        tile.store.moveInto(tile.store.draggingUrl, dir)
        d.accept(Qt.MoveAction)
      } else if (d.hasUrls) {
        tile.store.receiving = false
        tile.store.addFilesTo(d.urls, dir)
        d.accept(Qt.CopyAction)
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    radius: Style.space(6)
    color: tile.dragging
      ? Util.alpha(Commons.Color.accent, 0.22)
      : (mouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.10) : "transparent")
    border.width: tile.dragging || folderDrop.containsDrag ? Math.max(1, Style.spacing.hairline) : 0
    border.color: Commons.Color.accent
    clip: true

    // Sweeps left to right while a folder springs open, like the pinned buttons.
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * tile.springProgress
      radius: parent.radius
      color: Util.alpha(Commons.Color.accent, 0.25)
    }
  }

  Item {
    id: art
    anchors.top: parent.top
    anchors.topMargin: Style.space(10)
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width - Style.space(24)
    height: width * 0.75

    Image {
      id: thumb
      anchors.fill: parent
      visible: tile.image && status === Image.Ready
      source: tile.image ? String(tile.file.url || "") : ""
      sourceSize.width: Style.space(240)
      sourceSize.height: Style.space(180)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: true
    }

    Text {
      anchors.centerIn: parent
      visible: !thumb.visible
      text: (tile.store && tile.file) ? String(tile.store.iconFor(tile.file.name, tile.file.isDir) || "") : ""
      textFormat: Text.PlainText
      font.family: String((tile.store && tile.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Math.round(art.height * 0.6)
      renderType: Text.NativeRendering
      color: tile.file && tile.file.isDir ? Commons.Color.accent : Commons.Color.muted
    }
  }

  // Filenames are chosen by whoever made the file: PlainText, always.
  Text {
    anchors.top: art.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    text: tile.file ? String(tile.file.name || "") : ""
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WrapAnywhere
    maximumLineCount: 2
    elide: Text.ElideRight
    font.family: String((tile.store && tile.store.fontFamily) || Style.font.family || "")
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
    color: Commons.Color.foreground
  }

  DragHandler {
    id: tileDrag
    target: null
    acceptedButtons: Qt.LeftButton
    dragThreshold: Style.space(6)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: tileDrag.active ? Qt.ClosedHandCursor : (tile.file.isDir ? Qt.PointingHandCursor : Qt.OpenHandCursor)
    onPressed: {
      art.grabToImage(function(result) {
        if (result) tile.Drag.imageSource = result.url
      })
    }
    // Folders open in place on a single click; files open on a double click.
    // A finished drag-out is not a click, so draggingUrl is checked first.
    onClicked: if (tile.store && tile.file.isDir && tile.store.draggingUrl === "") tile.store.enterFolder(tile.file.path)
    onDoubleClicked: if (tile.store && !tile.file.isDir) tile.store.openFile(tile.file.path)
  }
}
