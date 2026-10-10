.pragma library

// Qt.resolvedUrl gives percent-encoded file URLs; commands and FileView need plain paths.
function localPath(url) {
    return decodeURIComponent(url.toString().replace(/^file:\/\//, ""));
}
