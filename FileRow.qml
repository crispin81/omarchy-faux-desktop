import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons

// One file in the folder, and the thing you drag.
//
// Drag.dragType: Drag.Automatic makes this a real Wayland drag
// (wl_data_device.start_drag), not an in-scene one. text/uri-list is what
// file managers, browsers and chat apps read; text/plain is for fields that
// only take text. The DragHandler moves no target - the compositor moves only
// the drag image.
//
// Adapted from jankeesvw/omarchy-downloads (MIT).
Item {
  id: row

  property var store: null
  // { name, url, path, size, isDir, modified }
  property var file: ({})

  readonly property bool dragging: store !== null && !!file && store.draggingUrl === file.url
  readonly property bool image: !!(store && file && !file.isDir && store.isImage(file.name))

  implicitHeight: Style.space(40)
  height: implicitHeight

  Drag.active: fileDrag.active
  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction
  Drag.mimeData: ({
    "text/uri-list": String(row.file.url || "") + "\r\n",
    "text/plain": String(row.file.url || "")
  })
  Drag.onDragStarted: if (row.store) row.store.draggingUrl = String(row.file.url || "")
  // Close on every finished drag: left open, the popup's full-screen click
  // catcher would swallow the next click in the app you dropped into. Wayland
  // hands back IgnoreAction even for accepted drops, so it can't be told apart.
  Drag.onDragFinished: {
    if (!row.store) return
    row.store.draggingUrl = ""
    // Dropped onto one of the panel's own folders: stay open to see it land.
    if (!row.store.internalDrop) row.store.open = false
    row.store.internalDrop = false
  }

  // Folders are drop targets: files from outside spring the folder open after
  // a moment (or land in it on drop); files from this panel move into it.
  readonly property bool springing: !!(store && file && file.isDir && store.springPath === file.path)
  property real springProgress: 0
  onSpringingChanged: {
    springSweep.stop()
    row.springProgress = 0
    if (row.springing) springSweep.start()
  }
  NumberAnimation {
    id: springSweep
    target: row
    property: "springProgress"
    from: 0
    to: 1
    duration: store ? store.springDelay : 400
  }

  DropArea {
    id: folderDrop
    anchors.fill: parent
    enabled: !!(row.file && row.file.isDir)
    keys: ["text/uri-list"]
    onEntered: function(drag) {
      if (!row.store) { drag.accepted = false; return }
      if (row.store.draggingUrl !== "") {
        // From this panel: no dropping a folder onto itself.
        if (row.store.draggingUrl === String(row.file.url || "")) { drag.accepted = false; return }
        drag.accept(Qt.MoveAction)
        return
      }
      row.store.springHover(String(row.file.path || ""))
      drag.accept(Qt.CopyAction)
    }
    onExited: if (row.store) row.store.springLeave(String(row.file.path || ""))
    onDropped: function(d) {
      if (!row.store) return
      var dir = String(row.file.path || "")
      row.store.springLeave(dir)
      if (row.store.draggingUrl !== "") {
        row.store.moveInto(row.store.draggingUrl, dir)
        d.accept(Qt.MoveAction)
      } else if (d.hasUrls) {
        row.store.receiving = false
        row.store.addFilesTo(d.urls, dir)
        d.accept(Qt.CopyAction)
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.space(4)
    color: row.dragging
      ? Util.alpha(Commons.Color.accent, 0.22)
      : (mouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.10) : "transparent")
    border.width: row.dragging || folderDrop.containsDrag ? Math.max(1, Style.spacing.hairline) : 0
    border.color: Commons.Color.accent
    clip: true

    // Sweeps left to right while a folder springs open, like the pinned buttons.
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * row.springProgress
      radius: parent.radius
      color: Util.alpha(Commons.Color.accent, 0.25)
    }
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)

    // Thumbnail for images, glyph for everything else.
    Item {
      Layout.alignment: Qt.AlignVCenter
      implicitWidth: Style.space(30)
      implicitHeight: Style.space(30)

      Image {
        id: thumb
        anchors.fill: parent
        visible: row.image && status === Image.Ready
        source: row.image ? String(row.file.url || "") : ""
        sourceSize.width: Style.space(60)
        sourceSize.height: Style.space(60)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
      }

      Text {
        anchors.centerIn: parent
        visible: !thumb.visible
        text: (row.store && row.file) ? String(row.store.iconFor(row.file.name, row.file.isDir) || "") : ""
        textFormat: Text.PlainText
        font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
        font.pixelSize: Style.font.icon
        renderType: Text.NativeRendering
        color: row.file && row.file.isDir ? Commons.Color.accent : Commons.Color.muted
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      Layout.alignment: Qt.AlignVCenter
      text: row.file ? String(row.file.name || "") : ""
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Style.font.body
      renderType: Text.NativeRendering
      color: Commons.Color.foreground
    }

    Text {
      Layout.alignment: Qt.AlignVCenter
      text: (row.store && row.file)
        ? String(row.store.formatAge(row.file.modified) || "")
          + (!row.file.isDir && row.file.size > 0 ? "  ·  " + String(row.store.formatSize(row.file.size) || "") : "")
        : ""
      textFormat: Text.PlainText
      font.family: String((row.store && row.store.fontFamily) || Style.font.family || "")
      font.pixelSize: Style.font.caption
      renderType: Text.NativeRendering
      color: Commons.Color.muted
    }
  }

  DragHandler {
    id: fileDrag
    target: null
    acceptedButtons: Qt.LeftButton
    dragThreshold: Style.space(6)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: fileDrag.active ? Qt.ClosedHandCursor : (row.file.isDir ? Qt.PointingHandCursor : Qt.OpenHandCursor)
    // Grab a picture of the row on press, so the drag carries something
    // recognisable. Press comes well before the drag threshold.
    onPressed: {
      row.grabToImage(function(result) {
        if (result) row.Drag.imageSource = result.url
      })
    }
    // Folders open in place on a single click; files open on a double click.
    // A finished drag-out is not a click, so draggingUrl is checked first.
    onClicked: if (row.store && row.file.isDir && row.store.draggingUrl === "") row.store.enterFolder(row.file.path)
    onDoubleClicked: if (row.store && !row.file.isDir) row.store.openFile(row.file.path)
  }
}
