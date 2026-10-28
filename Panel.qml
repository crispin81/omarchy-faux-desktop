import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Faux Desktop Folder: one folder, reachable from the bar.
//
// Hover (or click) the icon and the folder opens as a panel whose rows are
// drag handles, so a file goes straight into whatever window wants it. Drag
// files onto the icon or into the panel and they land in the folder.
// Right-click opens the folder in the file manager.
//
// All state lives in HotspotStore, a singleton: a bar widget is instantiated
// once per monitor, and a popup declared here would exist once per monitor
// too. This file is the view - an icon, a hover, and a drop target.
//
// Structure adapted from jankeesvw/omarchy-downloads (MIT).
Panel {
  id: root

  moduleName: "crispin81.faux-desktop"
  ipcTarget: "crispin81.faux-desktop"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Panel is a bare Item with no size of its own; size it from the content,
  // never from a child that fills it, or nothing decides the size.
  // The label sits in a rounded box, which doubles as a generous hover target.
  // slotWidth, when set, widens the box beyond the label.
  property int slotWidth: 0
  readonly property int labelSize: Style.font.bodySmall
  TextMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: root.labelSize
    text: "Faux Desktop"
  }
  // Twice the label's natural width: a bigger target to throw the pointer at.
  readonly property int pillWidth: Math.max(root.slotWidth,
    2 * (Math.ceil(labelMetrics.advanceWidth) + Style.space(20)))
  readonly property int pillHeight: Math.round((bar ? bar.barSize : Style.bar.sizeHorizontal) * 0.72)
  readonly property int barSlot: root.pillWidth + Style.space(8)
  readonly property real openPanelIndicatorWidth: root.pillWidth
  readonly property real openPanelIndicatorHeight: Style.bar.iconFont
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  property bool openOnHover: true
  property int hoverDelay: 0

  // The host assigns `settings` after construction, so read them on change as
  // well as on completion; completion alone sees an empty object.
  function applySettings() {
    HotspotStore.configure({
      folder: String(root.setting("folder", "")),
      sortBy: String(root.setting("sortBy", "newest")),
      dropAction: String(root.setting("dropAction", "copied")),
      viewMode: String(root.setting("viewMode", "list")),
      panelWidth: root.setting("panelWidth", 1040),
      panelHeight: root.setting("panelHeight", 600)
    })
    HotspotStore.fontFamily = root.fontFamily
    root.openOnHover = root.setting("openOnHover", true) !== false
    var d = Number(root.setting("hoverDelay", 0))
    root.hoverDelay = isFinite(d) ? Math.max(0, Math.min(2000, Math.round(d))) : 0
    var w = Number(root.setting("slotWidth", 0))
    root.slotWidth = isFinite(w) ? Math.max(0, Math.min(600, Math.round(w))) : 0
  }

  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  function showHere(byHover) {
    root.hoverArmed = false
    if (!HotspotStore.open) HotspotStore.showOn(button, root.bar, root, byHover)
  }

  // Mirror the store in both directions; each side checks before assigning so
  // nothing bounces. Only the widget that opened the store places the popup.
  onOpenedChanged: {
    if (root.opened) root.showHere(false)
    else if (HotspotStore.open) HotspotStore.hide()
  }

  Connections {
    target: HotspotStore
    function onOpenChanged() {
      if (HotspotStore.open && !root.opened) root.open()
      else if (!HotspotStore.open && root.opened) root.close()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    tooltipText: ""
    hasVisualContent: true

    Rectangle {
      anchors.centerIn: parent
      width: root.pillWidth
      height: root.pillHeight
      radius: Math.round(height / 3)
      color: dropZone.containsDrag || hover.hovered || root.opened
        ? Util.alpha(root.accent, 0.22)
        : Util.alpha(root.foreground, 0.10)
      border.width: Math.max(1, Style.spacing.hairline)
      border.color: dropZone.containsDrag || root.opened
        ? root.accent
        : Util.alpha(root.foreground, 0.25)

      Row {
        anchors.centerIn: parent
        spacing: Style.space(4)

        // Slanted speed lines: this box is a drag-and-drop target. They
        // slide while files are held over the box.
        Item {
          id: motion
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(9)
          height: root.labelSize
          // Slanted bottom-right to top-left: things heading up and in.
          rotation: 35
          transformOrigin: Item.Center
          property real shift: 0
          SequentialAnimation on shift {
            running: dropZone.containsDrag
            loops: Animation.Infinite
            onRunningChanged: if (!running) motion.shift = 0
            NumberAnimation { from: 0; to: -2.5; duration: 220; easing.type: Easing.InOutSine }
            NumberAnimation { from: -2.5; to: 0; duration: 220; easing.type: Easing.InOutSine }
          }
          Repeater {
            model: [ { y: 0.22, w: 0.65 }, { y: 0.50, w: 1.0 }, { y: 0.78, w: 0.45 } ]
            delegate: Rectangle {
              required property var modelData
              height: Math.max(1.5, Math.round(root.labelSize / 9))
              radius: height / 2
              width: motion.width * modelData.w
              x: -motion.shift
              y: motion.height * modelData.y - height / 2
              color: dropZone.containsDrag ? root.accent : root.foreground
              opacity: 0.75
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Faux Desktop"
          textFormat: Text.PlainText
          font.family: root.fontFamily
          font.pixelSize: root.labelSize
          renderType: Text.NativeRendering
          color: dropZone.containsDrag ? root.accent : root.foreground
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) HotspotStore.openFolder()
      else root.toggle()
    }
  }

  // The hotspot itself: resting the pointer on the icon opens the folder.
  // The hover area reaches up past the box to the screen's top edge, so the
  // pointer can be thrown straight up without aiming. The window clips the
  // overshoot.
  Item {
    id: hotArea
    x: 0
    y: -1000
    width: parent.width
    height: parent.height + 1000

    HoverHandler {
      id: hover
      enabled: root.openOnHover
      onHoveredChanged: {
        if (!hovered) {
          if (!HotspotStore.open) root.hoverArmed = true
        } else if (root.hoverDelay === 0 && root.hoverArmed && !HotspotStore.open) {
          root.showHere(true)
        }
      }
    }
  }

  // One hover, one opening. The open panel covers the bar, so the box sees
  // the pointer leave as soon as it opens and never again; re-arm when the
  // panel closes instead, unless the pointer is still sitting on the box.
  property bool hoverArmed: true
  Connections {
    target: HotspotStore
    function onOpenChanged() { if (!HotspotStore.open && !hover.hovered) root.hoverArmed = true }
  }

  // Only used with a non-zero delay; zero opens straight from the hover.
  Timer {
    interval: root.hoverDelay
    running: root.hoverDelay > 0 && hover.hovered && root.hoverArmed && root.openOnHover && !HotspotStore.open
    onTriggered: root.showHere(true)
  }

  // Files dragged onto the icon. Holding them there springs the panel open,
  // so they can be dropped into the folder view instead; letting go on the
  // icon adds them straight away.
  DropArea {
    id: dropZone
    anchors.fill: hotArea
    keys: ["text/uri-list"]
    onEntered: function(drag) { drag.accept(Qt.CopyAction) }
    onDropped: function(drop) {
      if (drop.hasUrls) {
        HotspotStore.addFiles(drop.urls)
        drop.accept(Qt.CopyAction)
      }
    }
  }

  Timer {
    interval: HotspotStore.springDelay
    running: dropZone.containsDrag && !HotspotStore.open
    onTriggered: root.showHere(false)
  }
}
