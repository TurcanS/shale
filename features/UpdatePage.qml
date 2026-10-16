import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// The control center's Update page: what a newer Shale changes, each commit message as it was written, and what
// the last update brought until it has been seen.
ColumnLayout {
    id: root
    spacing: Theme.gapS

    // One commit: its first line, then the rest of the message, then the commit and when it was made.
    component Change: C.Card {
        id: change
        required property var modelData
        readonly property string message: String(modelData.message || "")
        readonly property string subject: message.split("\n")[0]
        readonly property string body: message.slice(subject.length).replace(/^\n+/, "")
        Layout.fillWidth: true
        implicitHeight: changeText.implicitHeight + 2 * Theme.gapM
        ColumnLayout {
            id: changeText
            anchors.fill: parent
            anchors.margins: Theme.gapM
            spacing: Theme.gapXs
            C.Label {
                text: change.subject
                font.weight: Font.Medium
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            C.Label {
                visible: change.body !== ""
                text: change.body
                color: Theme.muted
                font.pixelSize: Theme.small
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            C.Label {
                text: String(change.modelData.sha || "").slice(0, 7) + (change.modelData.time ? " · " + Updates.ago(change.modelData.time) : "")
                font.family: Theme.mono
                font.pixelSize: Theme.caption
                color: Theme.muted
                Layout.fillWidth: true
            }
        }
    }

    // A newer Shale.
    ColumnLayout {
        visible: Updates.available
        Layout.fillWidth: true
        spacing: Theme.gapS
        C.Label {
            text: "Shale " + Updates.installed + "  →  " + Updates.latest
            font.family: Theme.mono
            font.weight: Font.Medium
            Layout.fillWidth: true
        }
        C.Label {
            readonly property var newest: Updates.commits.length ? Updates.commits[0] : null
            text: Updates.changes(Updates.count) + (newest && newest.time ? " · newest " + Updates.ago(newest.time) : "")
            color: Theme.muted
            font.pixelSize: Theme.small
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapXs
            spacing: Theme.gapS
            C.Button {
                text: "Update now"
                glyph: "update"
                accent: true
                enabled: Updates.source !== ""
                hint: "Runs ./install.sh --update in a terminal"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: Updates.install()
            }
            C.Button {
                text: "View on GitHub"
                glyph: "link"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: ShellState.openUrl(Updates.info.compare)
            }
        }
        C.Label {
            visible: Updates.source === ""
            text: "This copy doesn't know which folder it was installed from. Run ./install.sh --update in your Shale folder once; after that, Update now works from here."
            color: Theme.muted
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: Updates.commits
            Change {}
        }
        C.Label {
            visible: Updates.count > Updates.commits.length
            text: "And " + Updates.changes(Updates.count - Updates.commits.length) + " more on GitHub."
            color: Theme.muted
            font.pixelSize: Theme.small
            Layout.fillWidth: true
        }
        C.Button {
            text: "Skip this version"
            flat: true
            hint: "Hides it until a newer version arrives"
            Layout.alignment: Qt.AlignHCenter
            onClicked: Updates.skip()
        }
    }

    // What the last update brought.
    ColumnLayout {
        id: recentSection
        readonly property var recent: Updates.recent || ({})
        readonly property var brought: recent.commits || []
        visible: !!Updates.recent
        Layout.fillWidth: true
        Layout.topMargin: Updates.available ? Theme.gapL : 0
        spacing: Theme.gapS
        C.Label {
            text: "Updated  " + (recentSection.recent.from || "") + "  →  " + (recentSection.recent.to || "")
            font.family: Theme.mono
            font.weight: Font.Medium
            Layout.fillWidth: true
        }
        C.Label {
            text: recentSection.brought.length ? Updates.changes(recentSection.brought.length) + " in this update" : "The list of changes wasn't saved before this update; GitHub has it."
            color: Theme.muted
            font.pixelSize: Theme.small
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Repeater {
            model: recentSection.brought
            Change {}
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.gapXs
            spacing: Theme.gapS
            C.Button {
                visible: !recentSection.brought.length
                text: "View on GitHub"
                glyph: "link"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: ShellState.openUrl("https://github.com/TurcanS/shale/compare/" + recentSection.recent.from + "..." + recentSection.recent.to)
            }
            C.Button {
                text: "Got it"
                glyph: "check"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                onClicked: {
                    if (!Updates.available)
                        ShellState.detail = "";
                    Updates.seen();
                }
            }
        }
    }

    // Nothing to show: up to date, skipped, checking off, or GitHub unreachable.
    C.EmptyState {
        visible: !Updates.available && !Updates.recent
        Layout.fillWidth: true
        Layout.topMargin: Theme.gapL
        Layout.bottomMargin: Theme.gapL
        glyph: "update"
        readonly property bool local: Updates.installed.endsWith("-modified")
        title: !Updates.enabled ? "Update checks are off" : !Updates.installed ? "Version unknown" : local ? "Installed with local changes"
            : Updates.info.warning ? "Couldn't check for updates" : Updates.info.skipped ? "Update skipped" : "Shale is up to date"
        description: !Updates.enabled ? "Turn them on in Settings → General"
            : !Updates.installed ? "This copy wasn't installed with ./install.sh, so there's nothing to compare."
            : local ? "Shale " + Updates.installed + " has changes of its own, so it isn't compared with GitHub."
            : Updates.info.warning ? Updates.info.warning
            : Updates.info.skipped ? "It comes back when a newer version arrives."
            : Updates.info.checked ? "Shale " + Updates.installed + " · checked " + Updates.ago(Updates.info.checked) : "Shale " + Updates.installed
    }
}
