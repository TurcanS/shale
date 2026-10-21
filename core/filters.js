.pragma library

// Filter queries for the Logbook's saved filters and Filter view, as plain functions so they can run outside QML.
// parse() turns a query into a tree, or a refusal with the reason and where it is; matches() tests one order as the
// helper's day.orders returns it; run() lists the open orders a query selects, by due time.

const WORDS = ["today", "overdue", "repeats", "blocked"];
const PAIRS = {no: ["date", "site"], has: ["deadline", "notes"]};

function tokens(query) {
    const found = [];
    const pattern = /\s*([()&|!]|[^\s()&|!]+)/g;
    let match;
    while ((match = pattern.exec(query)) !== null)
        found.push({text: match[1], at: match.index + match[0].length - match[1].length});
    return found;
}

// {node} or {error, at}, where `at` is the character the problem starts at. `!` binds tightest, then `&`, then `|`.
function parse(query) {
    const source = String(query || "");
    const list = tokens(source);
    if (!list.length)
        return {error: "Write a query, for example today & @phone.", at: 0};
    let i = 0;
    const peek = () => list[i] ? list[i].text.toLowerCase() : "";
    const fail = text => {
        throw {refusal: text, at: list[i] ? list[i].at : source.length};
    };

    function primary() {
        const word = peek(), raw = list[i] ? list[i].text : "";
        if (word === "(") {
            i++;
            const node = either();
            if (peek() !== ")")
                fail("Close the bracket.");
            i++;
            return node;
        }
        if (!word || word === ")" || word === "&" || word === "|")
            fail(word ? "\"" + word + "\" needs a condition before it." : "The query ends too early.");
        i++;
        if (WORDS.indexOf(word) >= 0)
            return {op: word};
        if (word === "ahead") {
            if (!/^\d{1,3}$/.test(peek()) || Number(peek()) < 1)
                fail("Say how many days, as ahead 7.");
            return {op: "ahead", days: Number(list[i++].text)};
        }
        if (PAIRS.hasOwnProperty(word)) {
            if (PAIRS[word].indexOf(peek()) < 0)
                fail("Try " + PAIRS[word].map(other => word + " " + other).join(" or ") + ".");
            return {op: word + " " + list[i++].text.toLowerCase()};
        }
        let match = /^#([^\s#@/]+)(?:\/([^\s#@/]+))?$/.exec(raw);
        if (match)
            return {op: "site", site: match[1].toLowerCase(), section: match[2] ? match[2].toLowerCase() : null};
        match = /^@([^\s#@]+)$/.exec(raw);
        if (match)
            return {op: "tag", tag: match[1].toLowerCase()};
        match = /^p([1-4])$/.exec(word);
        if (match)
            return {op: "magnitude", priority: 5 - Number(match[1])};
        i--;
        fail("\"" + raw + "\" is not part of a query.");
    }

    function negation() {
        if (peek() !== "!")
            return primary();
        i++;
        return {op: "not", node: negation()};
    }

    function both() {
        let node = negation();
        while (peek() === "&") {
            i++;
            node = {op: "and", left: node, right: negation()};
        }
        return node;
    }

    function either() {
        let node = both();
        while (peek() === "|") {
            i++;
            node = {op: "or", left: node, right: both()};
        }
        return node;
    }

    try {
        const node = either();
        if (i < list.length)
            fail("\"" + list[i].text + "\" is not expected here.");
        return {node: node};
    } catch (problem) {
        if (problem && problem.refusal)
            return {error: problem.refusal, at: problem.at};
        throw problem;
    }
}

// Local midnight `days` calendar days after `now`'s date; setDate keeps daylight-saving days right.
function startOf(now, days) {
    const date = new Date(now);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + days);
    return date.getTime();
}

function same(name, wanted) {
    return String(name || "").toLowerCase() === wanted;
}

function matches(node, order, now) {
    const due = order.dueAt === undefined ? null : order.dueAt;
    switch (node.op) {
    case "and":
        return matches(node.left, order, now) && matches(node.right, order, now);
    case "or":
        return matches(node.left, order, now) || matches(node.right, order, now);
    case "not":
        return !matches(node.node, order, now);
    case "today":
        return due !== null && due >= startOf(now, 0) && due < startOf(now, 1);
    case "overdue":
        // An all-day order is late from the next day on; one with a time from that time on.
        return due !== null && due < (order.allDay ? startOf(now, 0) : now);
    case "ahead":
        return due !== null && due >= startOf(now, 0) && due < startOf(now, node.days);
    case "no date":
        return due === null;
    case "no site":
        return order.siteId === null || order.siteId === undefined;
    case "site":
        return same(order.site, node.site) && (node.section === null || same(order.section, node.section));
    case "tag":
        return (order.tags || []).some(tag => same(tag, node.tag));
    case "magnitude":
        return order.priority === node.priority;
    case "has deadline":
        return order.deadlineAt !== null && order.deadlineAt !== undefined;
    case "has notes":
        return Boolean(order.notes);
    case "repeats":
        return Boolean(order.rule);
    case "blocked":
        return order.openSubOrders > 0;
    }
    return false;
}

// {orders} (the open ones the query selects, by due time, undated last, then manual order) or {error, at}.
function run(query, orders, now) {
    const parsed = parse(query);
    if (parsed.error)
        return parsed;
    const due = order => order.dueAt === null || order.dueAt === undefined ? Infinity : order.dueAt;
    return {orders: orders.filter(order => order.doneAt == null && matches(parsed.node, order, now))
                          .sort((a, b) => due(a) - due(b) || (a.position || 0) - (b.position || 0) || a.id - b.id)};
}
