import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components" as C

// Control's Update page: what a newer Shale changes, each commit message as it was written, and what the last update
// brought until it has been seen.
ColumnLayout {
    id: root
    spacing: 10

    // One commit on the list: its first line, then the rest of the message, then the commit and when it was made.
    component Change: Item {
        id: change
        required property var modelData
        readonly property string message: String(modelData.message || "")
        readonly property string subject: message.split("\n")[0]
        readonly property string body: message.slice(subject.length).replace(/^\n+/, "")
        Layout.fillWidth: true
        implicitHeight: changeText.implicitHeight + 20
        ColumnLayout {
            id: changeText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 3
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
                color: Theme.textDim
                font.pixelSize: Theme.small
                wrapMode: Text.Wrap
                elide: Text.ElideNone
                Layout.fillWidth: true
            }
            C.Label {
                text: String(change.modelData.sha || "").slice(0, 7) + (change.modelData.time ? " · " + Updates.ago(change.modelData.time) : "")
                font.family: Theme.mono
                font.pixelSize: 11
                color: Theme.textDim
                Layout.fillWidth: true
                Layout.topMargin: 1
            }
        }
    }
    // The version line at the top of a section: an icon key (accent while something new waits), the versions and a
    // line under them.
    component Heading: RowLayout {
        id: heading
        property string title: ""
        property string note: ""
        property bool fresh: false
        Layout.fillWidth: true
        spacing: Theme.gapM
        C.GlyphTile {
            size: 36
            glyph: "update"
            selected: heading.fresh
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            C.Label {
                text: heading.title
                font.family: Theme.mono
                font.pixelSize: Theme.label
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }
            C.Label {
                visible: text !== ""
                text: heading.note
                color: Theme.textDim
                font.pixelSize: Theme.small
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }
    }

    // A newer Shale.
    ColumnLayout {
        visible: Updates.available
        Layout.fillWidth: true
        spacing: 10
        C.Card {
            Layout.fillWidth: true
            implicitHeight: available.implicitHeight + 2 * Theme.modulePadding + 2
            ColumnLayout {
                id: available
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.modulePadding + 1
                spacing: Theme.gapM
                Heading {
                    readonly property var newest: Updates.commits.length ? Updates.commits[0] : null
                    fresh: true
                    title: "Shale " + Updates.installed + "  →  " + Updates.latest
                    note: Updates.changes(Updates.count) + (newest && newest.time ? " · newest " + Updates.ago(newest.time) : "")
                }
                RowLayout {
                    Layout.fillWidth: true
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
                    color: Theme.textDim
                    font.pixelSize: Theme.small
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        C.SectionHeader {
            visible: Updates.commits.length > 0
            text: "What it changes"
        }
        C.Group {
            visible: Updates.commits.length > 0
            color: Theme.module
            Repeater {
                model: Updates.commits
                Change {}
            }
        }
        C.Label {
            visible: Updates.count > Updates.commits.length
            text: "And " + Updates.changes(Updates.count - Updates.commits.length) + " more on GitHub."
            color: Theme.textDim
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
        Layout.topMargin: Updates.available ? Theme.gapM : 0
        spacing: 10
        C.Card {
            Layout.fillWidth: true
            implicitHeight: recentHeading.implicitHeight + 2 * Theme.modulePadding + 2
            Heading {
                id: recentHeading
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.modulePadding + 1
                title: "Updated  " + (recentSection.recent.from || "") + "  →  " + (recentSection.recent.to || "")
                note: recentSection.brought.length ? Updates.changes(recentSection.brought.length) + " in this update" : "The list of changes wasn't saved before this update; GitHub has it."
            }
        }
        C.Group {
            visible: recentSection.brought.length > 0
            color: Theme.module
            Repeater {
                model: recentSection.brought
                Change {}
            }
        }
        RowLayout {
            Layout.fillWidth: true
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
