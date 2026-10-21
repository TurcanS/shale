.pragma library

// What each Logbook view lists, as plain functions so they can run outside QML (tested like core/day.js). `orders` is
// what day.orders answers: every open order and those cleared recently. A group is {key, label, orders}.

function startOf(now, days) {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + days);
    return date.getTime();
}

function open(order) {
    return order.doneAt === null || order.doneAt === undefined;
}

function dueOf(order) {
    return order.dueAt === null || order.dueAt === undefined ? Infinity : order.dueAt;
}

// Highest magnitude first, then the manual order.
function byMagnitude(a, b) {
    return b.priority - a.priority || (a.position || 0) - (b.position || 0) || a.id - b.id;
}

function byDue(a, b) {
    return dueOf(a) - dueOf(b) || byMagnitude(a, b);
}

function group(key, label, orders) {
    return {key: key, label: label, orders: orders};
}

// An all-day order is late from the next day on; one with a time from that time on (as `overdue` in core/filters.js).
function late(order, now) {
    return order.dueAt !== null && order.dueAt !== undefined && order.dueAt < (order.allDay ? startOf(now, 0) : now);
}

function dayName(at, now) {
    const days = Math.round((startOf(at, 0) - startOf(now, 0)) / 86400000);
    if (days === 0)
        return "Today";
    if (days === 1)
        return "Tomorrow";
    if (days === -1)
        return "Yesterday";
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(at).getDay()] + " " + new Date(at).getDate() + "/" + (new Date(at).getMonth() + 1);
}

function today(orders, now) {
    const start = startOf(now, 0), end = startOf(now, 1);
    const live = orders.filter(open);
    const overdue = live.filter(order => late(order, now)).sort(byDue);
    const isToday = order => order.dueAt >= start && order.dueAt < end && !late(order, now);
    const scheduled = live.filter(order => order.dueAt !== null && order.dueAt !== undefined && !order.allDay && isToday(order)).sort(byDue);
    const anytime = live.filter(order => order.dueAt !== null && order.dueAt !== undefined && order.allDay && isToday(order)).sort(byMagnitude);
    const cleared = orders.filter(order => !open(order) && order.doneAt >= start && order.doneAt < end).sort((a, b) => b.doneAt - a.doneAt);
    return [group("overdue", "OVERDUE", overdue), group("scheduled", "SCHEDULED", scheduled), group("anytime", "ANYTIME", anytime),
            group("cleared", "CLEARED", cleared)].filter(item => item.orders.length);
}

// The next seven days, one group each, empty days included so the strip always has seven columns.
function ahead(orders, now) {
    const live = orders.filter(open);
    const result = [];
    for (let day = 0; day < 7; day++) {
        const start = startOf(now, day), end = startOf(now, day + 1);
        const list = live.filter(order => order.dueAt !== null && order.dueAt !== undefined && order.dueAt >= start && order.dueAt < end &&
                                 !(day === 0 && late(order, now))).sort(byDue);
        result.push(group("day" + day, dayName(start, now).toUpperCase(), list));
    }
    return result;
}

function intake(orders) {
    const list = orders.filter(order => open(order) && (order.siteId === null || order.siteId === undefined)).sort((a, b) => b.createdAt - a.createdAt || b.id - a.id);
    return list.length ? [group("intake", "NEWEST FIRST", list)] : [];
}

// One site by section; orders in no section come first.
function site(orders, siteRow) {
    if (!siteRow)
        return [];
    const live = orders.filter(order => open(order) && order.siteId === siteRow.id);
    const result = [];
    const loose = live.filter(order => order.sectionId === null || order.sectionId === undefined).sort(byMagnitude);
    if (loose.length || !siteRow.sections.length)
        result.push(group("loose", "NO SECTION", loose));
    siteRow.sections.filter(section => !section.archived).forEach(section => {
        result.push(group("section" + section.id, section.name.toUpperCase(), live.filter(order => order.sectionId === section.id).sort(byMagnitude)));
    });
    return result;
}

// By site, as the spec says; Intake last.
function tag(orders, name) {
    const wanted = String(name).toLowerCase();
    const live = orders.filter(order => open(order) && (order.tags || []).some(item => String(item).toLowerCase() === wanted));
    const names = [];
    live.forEach(order => {
        if (names.indexOf(order.site || "") < 0)
            names.push(order.site || "");
    });
    names.sort((a, b) => (a === "") - (b === "") || a.localeCompare(b));
    return names.map(label => group("site" + label, label ? label.toUpperCase() : "INTAKE", live.filter(order => (order.site || "") === label).sort(byDue)));
}

// What core/filters.js run() selected, by due day.
function filter(orders, now) {
    const result = [];
    orders.forEach(order => {
        const label = order.dueAt === null || order.dueAt === undefined ? "NO DATE" : late(order, now) ? "OVERDUE" : dayName(order.dueAt, now).toUpperCase();
        let found = result.find(item => item.label === label);
        if (!found) {
            found = group("due" + label, label, []);
            result.push(found);
        }
        found.orders.push(order);
    });
    return result;
}

// The helper has already ranked a search by relevance, then due; nothing is re-sorted.
function search(orders) {
    return orders.length ? [group("results", "BY RELEVANCE", orders)] : [];
}

// History, per day, newest first.
function cleared(orders, now) {
    const result = [];
    orders.filter(order => !open(order)).sort((a, b) => b.doneAt - a.doneAt).forEach(order => {
        const label = dayName(order.doneAt, now).toUpperCase();
        let found = result.find(item => item.label === label);
        if (!found) {
            found = group("day" + startOf(order.doneAt, 0), label, []);
            result.push(found);
        }
        found.orders.push(order);
    });
    return result;
}

// A site's orders as columns, one per section.
function board(orders, siteRow) {
    return site(orders, siteRow);
}

// Open and cleared orders this week, for a site's progress figure; null when there are none.
function progress(orders, siteId, now) {
    const week = startOf(now, -6);
    const mine = orders.filter(order => order.siteId === siteId);
    const done = mine.filter(order => !open(order) && order.doneAt >= week).length;
    const total = done + mine.filter(open).length;
    return total ? Math.round(done / total * 100) : null;
}

// The sidebar's counts.
function counts(orders, now) {
    const live = orders.filter(open);
    const start = startOf(now, 0), end = startOf(now, 1);
    return {
        intake: live.filter(order => order.siteId === null || order.siteId === undefined).length,
        today: live.filter(order => late(order, now) || (order.dueAt >= start && order.dueAt < end)).length
    };
}

// The orders of every group in reading order: the rows the keys move through.
function flat(groups) {
    return groups.reduce((all, item) => all.concat(item.orders), []);
}

// {groups} for one view. `kind` is today, ahead, intake, site, tag, filter, search or cleared; `argument` is the site
// row or the tag name, and for filter and search `orders` is already what the query or the helper selected.
function view(kind, argument, orders, now) {
    switch (kind) {
    case "today":
        return today(orders, now);
    case "ahead":
        return ahead(orders, now);
    case "intake":
        return intake(orders);
    case "site":
        return site(orders, argument);
    case "tag":
        return tag(orders, argument);
    case "filter":
        return filter(orders, now);
    case "search":
        return search(orders);
    case "cleared":
        return cleared(orders, now);
    }
    return [];
}

// How long the hub takes to grow on into the Logbook, and the overshoot on its width: none when motion is reduced,
// shorter without overshoot in power saver. `leave` is Theme.leave, which is already 0 when motion is reduced.
function stageMotion(opening, reduced, lowPower, leave) {
    if (opening)
        return {duration: reduced ? 0 : lowPower ? 200 : 380, overshoot: !reduced && !lowPower};
    return {duration: leave + (reduced ? 0 : 60), overshoot: false};
}

// Whether the shift start shows by itself: it is due, and targets are on (with the daily target at 0 nothing of the
// shift is shown).
function shiftShows(due, targetsOn) {
    return Boolean(due) && Boolean(targetsOn);
}
