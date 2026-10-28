import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A layer-shell card with outside-click dismissal. During a native drag,
// only the card accepts input: a full-screen input region would cover every
// drop target beneath it, even though the rest of the surface is transparent.
PanelWindow {
  id: popup

  property Item anchorItem: null
  property QtObject bar: null
  property QtObject owner: null
  property bool open: false
  property bool dragging: false
  property real contentWidth: Style.space(520)
  property real contentHeight: Style.space(300)
  property bool focusPrimed: false
  default property alias content: body.data
  signal dismissed()
  // Bottom-right grip: live size while dragging, then once more on release.
  property bool resizable: true
  property real minWidth: 360
  property real minHeight: 240
  signal resizing(real w, real h)
  signal resized(real w, real h)

  function close() { popup.dismissed() }

  readonly property QtObject coordinatorKey: owner || popup

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPosition: bar ? bar.position : "top"
  readonly property real gap: Style.gapsOut
  // The bar window spans its whole screen, so its size says nothing about the
  // strip the bar paints; the strip's thickness is what the bar publishes.
  readonly property real barThickness: !bar ? 0
    : (typeof bar.barSizeFor === "function" && screen ? bar.barSizeFor(screen.name) : bar.barSize)
  readonly property real cardWidth: Math.min(contentWidth, Math.max(1, width - gap * 2
    - (barPosition === "left" || barPosition === "right" ? barThickness : 0)))
  readonly property real cardHeight: Math.min(contentHeight, Math.max(1, height - gap * 2
    - (barPosition === "top" || barPosition === "bottom" ? barThickness : 0)))
  readonly property point cardPosition: {
    anchorTracker.transform
    var p = anchorItem && anchorWindow ? anchorItem.mapToItem(anchorWindow.contentItem, 0, 0) : Qt.point(width - cardWidth, 0)
    var aw = anchorItem ? anchorItem.width : 0
    var ah = anchorItem ? anchorItem.height : 0
    // Left edge under the bar box, so resizing from the bottom-right corner
    // keeps the top-left still.
    var x = p.x
    var y = barThickness + gap
    if (barPosition === "bottom") y = height - barThickness - cardHeight - gap
    else if (barPosition === "left") { x = barThickness + gap; y = p.y + ah / 2 - cardHeight / 2 }
    else if (barPosition === "right") { x = width - barThickness - cardWidth - gap; y = p.y + ah / 2 - cardHeight / 2 }
    return Qt.point(Math.round(Math.max(gap, Math.min(x, width - cardWidth - gap))),
                    Math.round(Math.max(gap, Math.min(y, height - cardHeight - gap))))
  }

  TransformWatcher {
    id: anchorTracker
    a: popup.anchorItem
    b: popup.anchorWindow ? popup.anchorWindow.contentItem : null
  }

  // Opened by hovering: close again once the pointer wanders off. The popup
  // surface covers the bar, so the icon cannot report its own hover any more;
  // "near" is worked out here instead - over the card, over the icon, or in
  // the strip between them.
  property bool autoClose: false
  signal wandered()
  // Files dragged in from outside are over the card: never wander off then.
  property bool receiving: false

  readonly property rect anchorRect: {
    anchorTracker.transform
    if (!anchorItem || !anchorWindow) return Qt.rect(0, 0, 0, 0)
    var p = anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
    return Qt.rect(p.x, p.y, anchorItem.width, anchorItem.height)
  }

  function near(x, y) {
    var m = Style.space(14)
    if (x >= card.x - m && x <= card.x + card.width + m
        && y >= card.y - m && y <= card.y + card.height + m) return true
    var a = popup.anchorRect
    var top = Math.min(a.y, card.y), bottom = Math.max(a.y + a.height, card.y)
    return x >= a.x - m && x <= a.x + a.width + m && y >= top - m && y <= bottom + m
  }

  // A freshly mapped surface knows nothing about the pointer until it moves,
  // and a pointer resting on the bar box must not count as "wandered off" -
  // that is an open/close loop. Unknown counts as near.
  readonly property bool pointerNear: !surfaceHover.hovered
    || popup.near(surfaceHover.point.position.x, surfaceHover.point.position.y)

  HoverHandler { id: surfaceHover }

  Timer {
    interval: 250
    running: popup.open && popup.autoClose && !popup.dragging && !popup.receiving && !popup.pointerNear
      && !gripMouse.pressed
    onTriggered: popup.wandered()
  }

  screen: anchorWindow ? anchorWindow.screen : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  // Mapped once and kept: creating a layer surface on every hover is the lag
  // you feel. Closed, it is invisible and its input region is empty, so it
  // never takes a click or a hover from anything beneath it.
  visible: !!screen
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.namespace: "crispin81.faux-desktop"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: !open || dragging ? WlrKeyboardFocus.None
    : (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
  mask: Region {
    x: popup.dragging ? card.x : 0
    y: popup.dragging ? card.y : 0
    width: !popup.open ? 0 : (popup.dragging ? card.width : popup.width)
    height: !popup.open ? 0 : (popup.dragging ? card.height : popup.height)
  }

  onOpenChanged: {
    if (open) {
      focusPrimed = false
      prime.restart()
      body.forceActiveFocus()
      if (bar) bar.requestPopout(coordinatorKey)
    } else {
      prime.stop()
      if (bar && bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
    }
  }
  Timer { id: prime; interval: 75; onTriggered: popup.focusPrimed = true }

  // Any click outside the card closes the panel, a click on the bar
  // included. KeyboardPanel forwards bar clicks so another widget can open
  // in the same click, but a plugin only ever sees its own click targets
  // (PluginBarApi hands each plugin its own list), so from here the only
  // button that could be found is ours, and that one toggles closed anyway.
  MouseArea {
    anchors.fill: parent
    enabled: popup.open && !popup.dragging
    acceptedButtons: Qt.AllButtons
    onClicked: popup.close()
  }

  // Dismiss clicks on other monitors too, but let drags reach their windows.
  Variants {
    model: popup.open && !popup.dragging ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: !!popup.screen && modelData.name !== popup.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.namespace: "crispin81.faux-desktop-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: popup.close() }
      }
    }
  }

  BorderSurface {
    id: card
    visible: popup.open
    x: popup.cardPosition.x; y: popup.cardPosition.y
    width: popup.cardWidth; height: popup.cardHeight
    // The theme's menu surface: on a glass theme a see-through card that
    // Hyprland blurs (layer rule on the "crispin81.faux-desktop" namespace).
    color: Commons.Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
    padding: 0
    radius: Style.cornerRadius
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    FocusScope {
      id: body
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      focus: true
      Keys.onEscapePressed: popup.close()
    }

    Item {
      id: grip
      visible: popup.resizable
      width: 18
      height: 18
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: 3
      anchors.bottomMargin: 3
      z: 10

      // Three diagonal ridges, the usual resize-corner mark.
      Canvas {
        anchors.fill: parent
        property color ink: gripMouse.containsMouse || gripMouse.pressed ? Commons.Color.accent : Commons.Color.muted
        onInkChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = ink
          ctx.lineWidth = 1.5
          for (var i = 0; i < 3; i++) {
            var o = 4 + i * 5
            ctx.beginPath()
            ctx.moveTo(width - 1, o)
            ctx.lineTo(o, height - 1)
            ctx.stroke()
          }
        }
      }

      MouseArea {
        id: gripMouse
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.SizeFDiagCursor
        property real offX: 0
        property real offY: 0
        function sizeAt(mx, my) {
          var p = gripMouse.mapToItem(card, mx, my)
          return Qt.size(Math.max(popup.minWidth, Math.round(p.x + offX)),
                         Math.max(popup.minHeight, Math.round(p.y + offY)))
        }
        onPressed: function(m) {
          var p = gripMouse.mapToItem(card, m.x, m.y)
          offX = card.width - p.x
          offY = card.height - p.y
        }
        onPositionChanged: function(m) {
          if (!pressed) return
          var s = sizeAt(m.x, m.y)
          popup.resizing(s.width, s.height)
        }
        onReleased: function(m) {
          var s = sizeAt(m.x, m.y)
          popup.resized(Math.min(s.width, popup.cardWidth), Math.min(s.height, popup.cardHeight))
        }
      }
    }
  }
}
