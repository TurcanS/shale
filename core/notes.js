.pragma library

// Operator notes: one line at a time for the hub's footer. Written for Shale; your own lines join the list.
const LINES = [
    "Sediment settles one grain at a time.",
    "Basalt remembers every pour.",
    "A layer is only a day that stayed put.",
    "Fault lines are where the work was left.",
    "Mica flakes; so do plans. Re-file them.",
    "Nothing in the strata was hurried.",
    "Erosion is just slow clearing.",
    "Core sample taken. Looks like Tuesday.",
    "Granite does not answer email.",
    "Pressure makes slate; so does a deadline.",
    "Quartz keeps time better than you do.",
    "The Front moves whether you watch it or not.",
    "Small orders, deep seam.",
    "Cleared is cleared. The drum remembers.",
    "Ore first, polish later.",
    "Even the ridge started as silt.",
    "Check the gauge, not the clock on the wall.",
    "A quiet instrument is a working instrument.",
    "Tremors pass. Log them and carry on.",
    "One site at a time, one seam at a time.",
    "The best fossil is a finished order.",
    "Strike while the vein is warm.",
    "Today's layer is thin; lay it anyway.",
    "Carry over what must move, drop what mud.",
    "Calibrate: what is actually due?",
    "Shale splits along its own grain. Find yours.",
    "Bedrock is boring, and that is the point.",
    "No signal is also a reading.",
    "Dig where the ground is already soft.",
    "A short list is a sharp pick."
];

// The line for this moment: the shipped lines and `own` in turn, changing every `hours` hours. Empty without lines.
function pick(own, now, hours) {
    const lines = LINES.concat((own || []).filter(line => typeof line === "string" && line.trim() !== ""));
    if (!lines.length)
        return "";
    const slot = Math.floor(now / (Math.max(1, hours) * 3600000));
    return lines[((slot % lines.length) + lines.length) % lines.length];
}
