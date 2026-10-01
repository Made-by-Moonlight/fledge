import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#171e28"

  // userModel.lastUser is empty on a fresh install (nobody has logged in via
  // SDDM yet), which made sddm.login() fire with an empty username -> "user
  // unknown". Fall back to the first real user in the model (257 = NameRole,
  // Qt.UserRole + 1 in SDDM's UserModel).
  property string currentUser: {
    if (userModel.lastUser && userModel.lastUser !== "")
      return userModel.lastUser
    if (userModel.count > 0)
      return userModel.data(userModel.index(0, 0), 257)
    return ""
  }
  property bool loginFailed: false
  property int sessionIndex: {
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var name = (sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").toString()
      if (name.indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Image {
    anchors.fill: parent
    source: "background.png"
    fillMode: Image.PreserveAspectCrop
  }

  Column {
    anchors.centerIn: parent
    spacing: 26

    Image {
      id: logo
      source: "logo.png"
      width: 260
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: "made by moonlight"
      color: "#ffffff"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 18
      font.letterSpacing: 9
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
      text: root.currentUser
      color: "#6c7787"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 13
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Rectangle {
      id: field
      width: 360
      height: 44
      color: "#212a33"
      border.width: 2
      border.color: root.loginFailed ? "#e5626a" : "#2f3640"
      anchors.horizontalCenter: parent.horizontalCenter

      Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Repeater {
          model: Math.min(password.text.length, 32)
          Rectangle { width: 7; height: 7; radius: 3.5; color: "#f4af03" }
        }
      }

      TextInput {
        id: password
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        echoMode: TextInput.Password
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 16
        font.letterSpacing: 3
        passwordCharacter: "\u2022"
        color: "transparent"
        selectionColor: "transparent"
        selectedTextColor: "transparent"
        cursorDelegate: Item {}
        focus: true

        onTextChanged: root.loginFailed = false

        Keys.onPressed: {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            sddm.login(root.currentUser, password.text, root.sessionIndex)
            event.accepted = true
          }
        }
      }
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
