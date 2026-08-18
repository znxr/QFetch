import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.znxr.qfetch"
  ipcTarget: "io.github.znxr.qfetch"
  manageIpc: false

  property string method: "GET"
  property string requestUrl: "https://httpbin.org/get"
  property string requestHeaders: "{}"
  property string requestBody: ""
  property string responseText: ""
  property string responseHeaders: ""
  property string statusText: "Ready"
  property int responseStatus: 0
  property int elapsedMs: 0
  property real requestStartedAt: 0
  property bool requestRunning: false
  property string copyLabel: "COPY"
  property var anchorItem: null
  property var hostWidget: null
  property string headersMode: "JSON"
  property string bodyMode: "JSON"

  readonly property color foreground: Color.foreground
  readonly property color muted: Qt.darker(root.foreground, 1.6)
  readonly property color panelBackground: Color.background
  readonly property int gap: Style.space(10)
  readonly property bool copyEnabled: root.responseStatus > 0 && root.responseText !== ""

  ListModel { id: headersFormModel }
  ListModel { id: bodyFormModel }
  property alias headersEditorModel: headersFormModel
  property alias bodyEditorModel: bodyFormModel

  function open() {
    root.controller.show()
    Qt.callLater(function() { urlField.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.close() }

  function parseHeaders() {
    var parsed
    try {
      parsed = JSON.parse(headersField.text || "{}")
    } catch (error) {
      root.statusText = "Headers must be valid JSON"
      return null
    }
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") {
      root.statusText = "Headers must be a JSON object"
      return null
    }
    return parsed
  }

  function prettyBody(raw) {
    try { return JSON.stringify(JSON.parse(raw), null, 2) }
    catch (error) { return raw }
  }

  function loadRows(raw, model, emptyMessage) {
    var object
    try { object = JSON.parse(raw || "{}") }
    catch (error) { root.statusText = emptyMessage; return false }
    if (object === null || Array.isArray(object) || typeof object !== "object") {
      root.statusText = emptyMessage
      return false
    }
    model.clear()
    for (var key in object) {
      var value = object[key]
      model.append({ fieldName: key, fieldValue: typeof value === "object" ? JSON.stringify(value) : String(value) })
    }
    if (model.count === 0) model.append({ fieldName: "", fieldValue: "" })
    return true
  }

  function rowsObject(model) {
    var object = {}
    for (var i = 0; i < model.count; i++) {
      var row = model.get(i)
      var value = String(row.fieldValue)
      try { object[String(row.fieldName)] = JSON.parse(value) }
      catch (error) { object[String(row.fieldName)] = value }
    }
    return object
  }

  function setEditorMode(kind, mode) {
    if (kind === "headers") {
      if (mode === "FORM" && !loadRows(headersField.text, root.headersEditorModel, "Headers must be a JSON object")) return
      headersMode = mode
    } else {
      if (mode === "FORM" && !loadRows(bodyField.text, root.bodyEditorModel, "Body must be a JSON object in form mode")) return
      bodyMode = mode
    }
  }

  function sendRequest() {
    if (root.requestRunning || !urlField.text.trim()) return
    var headers = headersMode === "FORM" ? rowsObject(root.headersEditorModel) : root.parseHeaders()
    if (headers === null) return

    root.requestRunning = true
    root.statusText = "Sending..."
    root.responseStatus = 0
    root.responseText = ""
    root.responseHeaders = ""
    root.copyLabel = "COPY"
    root.elapsedMs = 0
    root.requestStartedAt = Date.now()
    requestClock.restart()

    var xhr = new XMLHttpRequest()
    xhr.open(methodField.value, urlField.text.trim())
    for (var key in headers) xhr.setRequestHeader(key, String(headers[key]))
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.requestRunning = false
      requestClock.stop()
      root.elapsedMs = Date.now() - root.requestStartedAt
      root.responseStatus = xhr.status
      root.responseHeaders = xhr.getAllResponseHeaders() || "(no response headers)"
      root.responseText = root.prettyBody(xhr.responseText || "(empty response)")
      root.statusText = xhr.status > 0
        ? String(xhr.status) + " " + (xhr.statusText || "OK")
        : "Request failed"
    }
    xhr.onerror = function() {
      root.requestRunning = false
      requestClock.stop()
      root.elapsedMs = Date.now() - root.requestStartedAt
      root.statusText = "Network error"
      root.responseText = "The request could not be completed. Check the URL and network connection."
    }
    xhr.ontimeout = function() {
      root.requestRunning = false
      requestClock.stop()
      root.elapsedMs = Date.now() - root.requestStartedAt
      root.statusText = "Request timed out"
    }
    xhr.timeout = 30000
    var outgoingBody = bodyMode === "FORM" ? JSON.stringify(rowsObject(root.bodyEditorModel), null, 2) : bodyField.text
    xhr.send(methodField.value === "GET" || methodField.value === "HEAD" ? null : outgoingBody)
  }

  function resetRequest() {
    methodField.value = "GET"
    urlField.text = "https://httpbin.org/get"
    headersField.text = "{}"
    bodyField.text = ""
    headersEditorModel.clear()
    bodyEditorModel.clear()
    headersMode = "JSON"
    bodyMode = "JSON"
    root.responseText = ""
    root.responseHeaders = ""
    root.copyLabel = "COPY"
    root.statusText = "Ready"
    root.responseStatus = 0
  }

  function copyResponse() {
    if (!root.copyEnabled) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.responseText) + " | wl-copy"])
    root.copyLabel = "COPIED"
    copyFeedbackTimer.restart()
  }

  Timer {
    id: copyFeedbackTimer
    interval: 1400
    repeat: false
    onTriggered: root.copyLabel = "COPY"
  }

  Timer {
    id: requestClock
    interval: 1000
    repeat: true
    onTriggered: root.elapsedMs += 1000
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(760))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: root.gap

          RowLayout {
            width: parent.width
            spacing: root.gap

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: "QFETCH"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: "HTTP request workbench"
                color: root.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)
            Dropdown {
              id: methodField
              options: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]
              value: "GET"
              foreground: root.foreground
              fontFamily: Style.font.family
              Layout.preferredWidth: Style.space(106)
              Layout.preferredHeight: Style.spacing.controlHeight
            }
            TextField {
              id: urlField
              Layout.fillWidth: true
              Layout.preferredHeight: Style.spacing.controlHeight
              text: root.requestUrl
              placeholderText: "https://api.example.com/endpoint"
              color: root.foreground
              font.family: Style.font.family
              selectByMouse: true
              enabled: !root.requestRunning
              Keys.onReturnPressed: root.sendRequest()
            }
            Rectangle {
              Layout.preferredWidth: Style.space(86)
              Layout.preferredHeight: Style.spacing.controlHeight
              radius: Style.cornerRadius
              color: root.requestRunning ? root.muted : Color.accent
              Text { anchors.centerIn: parent; text: root.requestRunning ? "WAIT" : "SEND"; color: Color.background; font.bold: true; font.family: Style.font.family }
              MouseArea { anchors.fill: parent; enabled: !root.requestRunning; onClicked: root.sendRequest() }
            }
          }

          RowLayout {
            width: parent.width
            spacing: root.gap
            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: parent.width / 2
              RowLayout {
                Layout.fillWidth: true
                Text { text: "HEADERS"; color: root.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
                Rectangle { width: Style.space(42); height: Style.space(24); radius: Style.cornerRadius; color: root.headersMode === "JSON" ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"; Text { anchors.centerIn: parent; text: "JSON"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption } MouseArea { anchors.fill: parent; onClicked: root.setEditorMode("headers", "JSON") } }
                Rectangle { width: Style.space(48); height: Style.space(24); radius: Style.cornerRadius; color: root.headersMode === "FORM" ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"; Text { anchors.centerIn: parent; text: "FORM"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption } MouseArea { anchors.fill: parent; onClicked: root.setEditorMode("headers", "FORM") } }
              }
              TextArea {
                id: headersField
                visible: root.headersMode === "JSON"
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(112)
                text: root.requestHeaders
                color: root.foreground
                placeholderTextColor: root.muted
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground
                leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
                rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
                topPadding: Style.spacing.inputPaddingY + Border.top(_borderSpec)
                bottomPadding: Style.spacing.inputPaddingY + Border.bottom(_borderSpec)
                readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Color.accent)
                background: BorderSurface {
                  color: Style.controlFill(parent.activeFocus, parent.hovered, root.foreground, Color.accent)
                  borderSpec: parent._borderSpec
                  radius: Style.cornerRadius
                }
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                placeholderText: '{"Authorization": "Bearer ..."}'
              }
              Flickable {
                visible: root.headersMode === "FORM"
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(112)
                contentWidth: width
                contentHeight: headersRows.implicitHeight
                clip: true
                onContentHeightChanged: Qt.callLater(function() { if (contentHeight > height) contentY = contentHeight - height })
                Column {
                  id: headersRows
                  width: parent.width
                  spacing: Style.space(4)
                  Repeater {
                    model: root.headersEditorModel
                    delegate: RowLayout {
                      required property int index
                      required property string fieldName
                      required property string fieldValue
                      width: headersRows.width
                      height: Style.spacing.controlHeight
                      TextField { Layout.fillWidth: true; placeholderText: "Header"; text: fieldName; onEditingFinished: root.headersEditorModel.setProperty(index, "fieldName", text) }
                      TextField { Layout.fillWidth: true; placeholderText: "Value"; text: fieldValue; onEditingFinished: root.headersEditorModel.setProperty(index, "fieldValue", text) }
                      Rectangle {
                        Layout.preferredWidth: Style.space(28)
                        Layout.fillHeight: true
                        radius: Style.cornerRadius
                        color: "transparent"
                        Text { anchors.centerIn: parent; text: "-"; color: root.muted; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.headersEditorModel.remove(index) }
                      }
                    }
                  }
                  Rectangle {
                    width: Style.space(72); height: Style.spacing.controlHeight; radius: Style.cornerRadius
                    color: "transparent"; border.color: root.muted
                    Text { anchors.centerIn: parent; text: "+ ADD"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    MouseArea { anchors.fill: parent; onClicked: root.headersEditorModel.append({ fieldName: "", fieldValue: "" }) }
                  }
                }
              }
            }
            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: parent.width / 2
              RowLayout {
                Layout.fillWidth: true
                Text { text: "BODY"; color: root.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
                Rectangle { width: Style.space(42); height: Style.space(24); radius: Style.cornerRadius; color: root.bodyMode === "JSON" ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"; Text { anchors.centerIn: parent; text: "JSON"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption } MouseArea { anchors.fill: parent; onClicked: root.setEditorMode("body", "JSON") } }
                Rectangle { width: Style.space(48); height: Style.space(24); radius: Style.cornerRadius; color: root.bodyMode === "FORM" ? Style.selectedFillFor(root.foreground, Color.accent) : "transparent"; Text { anchors.centerIn: parent; text: "FORM"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption } MouseArea { anchors.fill: parent; onClicked: root.setEditorMode("body", "FORM") } }
              }
              TextArea {
                id: bodyField
                visible: root.bodyMode === "JSON"
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(112)
                color: root.foreground
                placeholderTextColor: root.muted
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground
                leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
                rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
                topPadding: Style.spacing.inputPaddingY + Border.top(_borderSpec)
                bottomPadding: Style.spacing.inputPaddingY + Border.bottom(_borderSpec)
                readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Color.accent)
                background: BorderSurface {
                  color: Style.controlFill(parent.activeFocus, parent.hovered, root.foreground, Color.accent)
                  borderSpec: parent._borderSpec
                  radius: Style.cornerRadius
                }
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                placeholderText: '{"hello": "world"}'
              }
              Flickable {
                visible: root.bodyMode === "FORM"
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(112)
                contentWidth: width
                contentHeight: bodyRows.implicitHeight
                clip: true
                onContentHeightChanged: Qt.callLater(function() { if (contentHeight > height) contentY = contentHeight - height })
                Column {
                  id: bodyRows
                  width: parent.width
                  spacing: Style.space(4)
                  Repeater {
                    model: root.bodyEditorModel
                    delegate: RowLayout {
                      required property int index
                      required property string fieldName
                      required property string fieldValue
                      width: bodyRows.width
                      height: Style.spacing.controlHeight
                      TextField { Layout.fillWidth: true; placeholderText: "Field"; text: fieldName; onEditingFinished: root.bodyEditorModel.setProperty(index, "fieldName", text) }
                      TextField { Layout.fillWidth: true; placeholderText: "Value"; text: fieldValue; onEditingFinished: root.bodyEditorModel.setProperty(index, "fieldValue", text) }
                      Rectangle {
                        Layout.preferredWidth: Style.space(28)
                        Layout.fillHeight: true
                        radius: Style.cornerRadius
                        color: "transparent"
                        Text { anchors.centerIn: parent; text: "-"; color: root.muted; font.bold: true }
                        MouseArea { anchors.fill: parent; onClicked: root.bodyEditorModel.remove(index) }
                      }
                    }
                  }
                  Rectangle {
                    width: Style.space(72); height: Style.spacing.controlHeight; radius: Style.cornerRadius
                    color: "transparent"; border.color: root.muted
                    Text { anchors.centerIn: parent; text: "+ ADD"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    MouseArea { anchors.fill: parent; onClicked: root.bodyEditorModel.append({ fieldName: "", fieldValue: "" }) }
                  }
                }
              }
            }
          }

          RowLayout {
            width: parent.width
            Text { text: "RESPONSE"; color: root.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
            Text { text: root.responseStatus > 0 ? root.statusText + " · " + root.elapsedMs + " ms" : ""; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
            Rectangle {
              Layout.preferredWidth: Style.space(76); Layout.preferredHeight: Style.space(28); radius: Style.cornerRadius
              color: root.copyEnabled ? "transparent" : Qt.darker(root.panelBackground, 1.15)
              border.color: root.copyEnabled ? root.muted : Qt.darker(root.muted, 1.4)
              opacity: root.copyEnabled ? 1 : 0.5
              Text { anchors.centerIn: parent; text: root.copyLabel; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; enabled: root.copyEnabled; onClicked: root.copyResponse() }
            }
            Rectangle {
              Layout.preferredWidth: Style.space(76); Layout.preferredHeight: Style.space(28); radius: Style.cornerRadius; color: "transparent"; border.color: root.muted
              Text { anchors.centerIn: parent; text: "RESET"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.resetRequest() }
            }
          }

          TextArea {
            width: parent.width
            height: Style.space(210)
            text: root.responseText || "Send a request to inspect the response."
            color: root.foreground
            placeholderTextColor: root.muted
            selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
            selectedTextColor: root.foreground
            leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
            rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
            topPadding: Style.spacing.inputPaddingY + Border.top(_borderSpec)
            bottomPadding: Style.spacing.inputPaddingY + Border.bottom(_borderSpec)
            readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), root.foreground, Color.accent)
            background: BorderSurface {
              color: Style.controlFill(parent.activeFocus, parent.hovered, root.foreground, Color.accent)
              borderSpec: parent._borderSpec
              radius: Style.cornerRadius
            }
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
          }

          Text {
            width: parent.width
            text: root.responseHeaders ? "RESPONSE HEADERS\n" + root.responseHeaders : "Click SEND to run the request."
            color: root.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
