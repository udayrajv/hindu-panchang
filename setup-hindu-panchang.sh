#!/bin/bash

set -e

PROJECT="hindu-panchang"

echo "Creating Hindu Panchang iCal project..."

mkdir -p "$PROJECT"/{src,scripts,config,public/calendars/dublin-ca,.github/workflows}

cd "$PROJECT"

cat > package.json <<'EOF'
{
  "name": "hindu-panchang",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "generate": "tsx scripts/generate.ts",
    "build": "npm run generate",
    "dev": "wrangler dev",
    "deploy": "npm run generate && wrangler deploy"
  },
  "dependencies": {
    "@ishubhamx/panchangam-js": "^3.0.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20261004.0",
    "tsx": "^4.20.5",
    "typescript": "^5.9.2",
    "wrangler": "^4.45.0"
  }
}
EOF

cat > wrangler.jsonc <<'EOF'
{
  "$schema": "./node_modules/wrangler/config-schema.json",
  "name": "hindu-panchang",
  "compatibility_date": "2026-10-04",
  "assets": {
    "directory": "./public"
  }
}
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": [
    "src/**/*.ts",
    "scripts/**/*.ts"
  ]
}
EOF

cat > config/locations.json <<'EOF'
{
  "dublin-ca": {
    "name": "Dublin, California, USA",
    "latitude": 37.7022,
    "longitude": -121.9358,
    "elevation": 105,
    "timezone": "America/Los_Angeles"
  }
}
EOF

cat > src/index.ts <<'EOF'
export default {
  async fetch(request: Request): Promise<Response> {
    return new Response(
      "Hindu Panchang Calendar\\n\\n" +
      "Available calendars:\\n" +
      "/calendars/dublin-ca/all.ics\\n" +
      "/calendars/dublin-ca/festivals.ics\\n" +
      "/calendars/dublin-ca/vrat.ics\\n" +
      "/calendars/dublin-ca/rahu-kalam.ics\\n",
      {
        headers: {
          "content-type": "text/plain; charset=utf-8"
        }
      }
    );
  }
};
EOF

cat > scripts/generate.ts <<'EOF'
import fs from "node:fs";
import path from "node:path";

import {
  getPanchangam,
  Observer
} from "@ishubhamx/panchangam-js";

type Location = {
  name: string;
  latitude: number;
  longitude: number;
  elevation: number;
  timezone: string;
};

type CalendarEvent = {
  uid: string;
  title: string;
  description?: string;
  category: "festival" | "vrat" | "rahu-kalam";
  allDay: boolean;
  date?: string;
  start?: Date;
  end?: Date;
};

const locations: Record<string, Location> = JSON.parse(
  fs.readFileSync(
    path.resolve("config/locations.json"),
    "utf8"
  )
);

const START_YEAR = Number(process.env.START_YEAR || 2026);
const END_YEAR = Number(process.env.END_YEAR || 2027);

function pad(n: number): string {
  return String(n).padStart(2, "0");
}

function dateKey(date: Date, timezone: string): string {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(date);

  const get = (type: string) =>
    p.find(x => x.type === type)?.value ?? "";

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function timezoneOffsetMinutes(
  date: Date,
  timezone: string
): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    timeZoneName: "longOffset",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).formatToParts(date);

  const value =
    parts.find(p => p.type === "timeZoneName")?.value || "GMT";

  const m = value.match(
    /^GMT([+-])(\d{1,2})(?::(\d{2}))?$/
  );

  if (!m) return 0;

  const sign = m[1] === "+" ? 1 : -1;
  const hours = Number(m[2]);
  const minutes = Number(m[3] || 0);

  return sign * (hours * 60 + minutes);
}

function localNoonAsDate(
  year: number,
  month: number,
  day: number,
  timezone: string
): Date {
  // Start with an approximate UTC representation.
  const guess = new Date(
    Date.UTC(year, month - 1, day, 12, 0, 0)
  );

  // Determine the actual local offset and correct the instant.
  const offset = timezoneOffsetMinutes(guess, timezone);

  return new Date(
    guess.getTime() - offset * 60 * 1000
  );
}

function localParts(
  date: Date,
  timezone: string
) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23"
  }).formatToParts(date);

  const get = (type: string) =>
    parts.find(x => x.type === type)?.value || "00";

  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")),
    minute: Number(get("minute")),
    second: Number(get("second"))
  };
}

function icsDate(date: Date, timezone: string): string {
  const p = localParts(date, timezone);

  return (
    `${p.year}${pad(p.month)}${pad(p.day)}` +
    `T${pad(p.hour)}${pad(p.minute)}${pad(p.second)}`
  );
}

function icsDateOnly(date: string): string {
  return date.replaceAll("-", "");
}

function escapeICS(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

function utcStamp(date = new Date()): string {
  return (
    date.getUTCFullYear().toString() +
    pad(date.getUTCMonth() + 1) +
    pad(date.getUTCDate()) +
    "T" +
    pad(date.getUTCHours()) +
    pad(date.getUTCMinutes()) +
    pad(date.getUTCSeconds()) +
    "Z"
  );
}

function festivalCategory(
  name: string,
  category?: string
): "festival" | "vrat" {
  const n = name.toLowerCase();
  const c = String(category || "").toLowerCase();

  const vratKeywords = [
    "sankashti",
    "ekadashi",
    "pradosh",
    "shivaratri",
    "amavasya",
    "purnima vrat",
    "vrat",
    "upavasa",
    "sankranti"
  ];

  if (
    vratKeywords.some(k => n.includes(k)) ||
    c.includes("vrat") ||
    c.includes("fast")
  ) {
    return "vrat";
  }

  return "festival";
}

function addEvent(
  events: CalendarEvent[],
  event: CalendarEvent
) {
  events.push(event);
}

function generateLocationEvents(
  locationId: string,
  location: Location,
  year: number
): CalendarEvent[] {
  const events: CalendarEvent[] = [];

  const observer = new Observer(
    location.latitude,
    location.longitude,
    location.elevation
  );

  const start = new Date(Date.UTC(year, 0, 1));
  const end = new Date(Date.UTC(year + 1, 0, 1));

  for (
    let cursor = new Date(start);
    cursor < end;
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  ) {
    const y = cursor.getUTCFullYear();
    const m = cursor.getUTCMonth() + 1;
    const d = cursor.getUTCDate();

    const noon = localNoonAsDate(
      y,
      m,
      d,
      location.timezone
    );

    const offset = timezoneOffsetMinutes(
      noon,
      location.timezone
    );

    const p: any = getPanchangam(
      noon,
      observer,
      {
        timezoneOffset: offset
      }
    );

    const date = `${y}-${pad(m)}-${pad(d)}`;

    // Festivals / Vratas
    if (Array.isArray(p.festivals)) {
      for (const festival of p.festivals) {
        const name = String(
          festival?.name || festival
        ).trim();

        if (!name) continue;

        const category = festivalCategory(
          name,
          festival?.category
        );

        addEvent(events, {
          uid:
            `${locationId}-${date}-` +
            name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
          title: name,
          description:
            `${name} — ${location.name}`,
          category,
          allDay: true,
          date
        });
      }
    }

    // Rahu Kalam
    const rahu = p.rahuKalam;

    if (rahu?.start && rahu?.end) {
      addEvent(events, {
        uid: `${locationId}-${date}-rahu-kalam`,
        title: "Rahu Kalam",
        description:
          `Rahu Kalam for ${location.name}`,
        category: "rahu-kalam",
        allDay: false,
        start: new Date(rahu.start),
        end: new Date(rahu.end)
      });
    }
  }

  return events;
}

function toICS(
  events: CalendarEvent[],
  location: Location,
  feedName: string
): string {
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Hindu Panchang//Dublin CA//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:Hindu Panchang - ${feedName} - ${location.name}`,
    `X-WR-TIMEZONE:${location.timezone}`,
    "X-PUBLISHED-TTL:PT24H"
  ];

  for (const event of events) {
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:${escapeICS(event.uid)}`);
    lines.push(`DTSTAMP:${utcStamp()}`);

    if (event.allDay && event.date) {
      lines.push(
        `DTSTART;VALUE=DATE:${icsDateOnly(event.date)}`
      );

      const next = new Date(
        `${event.date}T12:00:00Z`
      );

      next.setUTCDate(next.getUTCDate() + 1);

      const nextDate =
        `${next.getUTCFullYear()}-${pad(next.getUTCMonth() + 1)}-${pad(next.getUTCDate())}`;

      lines.push(
        `DTEND;VALUE=DATE:${icsDateOnly(nextDate)}`
      );
    } else if (event.start && event.end) {
      lines.push(
        `DTSTART;TZID=${location.timezone}:${icsDate(event.start, location.timezone)}`
      );
      lines.push(
        `DTEND;TZID=${location.timezone}:${icsDate(event.end, location.timezone)}`
      );
    }

    lines.push(
      `SUMMARY:${escapeICS(event.title)}`
    );

    if (event.description) {
      lines.push(
        `DESCRIPTION:${escapeICS(event.description)}`
      );
    }

    lines.push("END:VEVENT");
  }

  lines.push("END:VCALENDAR");

  return lines.join("\r\n") + "\r\n";
}

function writeCalendar(
  locationId: string,
  location: Location,
  feed: string,
  events: CalendarEvent[]
) {
  const directory = path.resolve(
    "public",
    "calendars",
    locationId
  );

  fs.mkdirSync(directory, { recursive: true });

  let filtered: CalendarEvent[];

  switch (feed) {
    case "festivals":
      filtered = events.filter(
        e => e.category === "festival"
      );
      break;

    case "vrat":
      filtered = events.filter(
        e => e.category === "vrat"
      );
      break;

    case "rahu-kalam":
      filtered = events.filter(
        e => e.category === "rahu-kalam"
      );
      break;

    default:
      filtered = events;
  }

  const filename = path.join(
    directory,
    `${feed}.ics`
  );

  fs.writeFileSync(
    filename,
    toICS(filtered, location, feed),
    "utf8"
  );

  console.log(
    `Created ${filename} (${filtered.length} events)`
  );
}

for (const [locationId, location] of Object.entries(
  locations
)) {
  const allEvents: CalendarEvent[] = [];

  for (
    let year = START_YEAR;
    year <= END_YEAR;
    year++
  ) {
    console.log(
      `Generating ${location.name} ${year}...`
    );

    allEvents.push(
      ...generateLocationEvents(
        locationId,
        location,
        year
      )
    );
  }

  writeCalendar(
    locationId,
    location,
    "all",
    allEvents
  );

  writeCalendar(
    locationId,
    location,
    "festivals",
    allEvents
  );

  writeCalendar(
    locationId,
    location,
    "vrat",
    allEvents
  );

  writeCalendar(
    locationId,
    location,
    "rahu-kalam",
    allEvents
  );
}
EOF

cat > .github/workflows/generate.yml <<'EOF'
name: Generate Hindu Panchang Calendars

on:
  workflow_dispatch:
  schedule:
    # First day of every month at 02:00 UTC.
    - cron: "0 2 1 * *"

permissions:
  contents: write

jobs:
  generate:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - name: Install dependencies
        run: npm install

      - name: Generate calendars
        run: npm run generate
        env:
          START_YEAR: 2026
          END_YEAR: 2030

      - name: Commit generated calendars
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

          git add public/calendars

          if git diff --cached --quiet; then
            echo "No calendar changes."
          else
            git commit -m "Update Hindu Panchang calendars"
            git push
          fi
EOF

cat > .gitignore <<'EOF'
node_modules/
.wrangler/
.DS_Store
dist/
.env
EOF

cat > README.md <<'EOF'
# Hindu Panchang iCalendar

Location-aware Hindu Panchang calendars designed for Apple Calendar and
other iCalendar-compatible applications.

## Default location

Dublin, California, USA

Timezone:

America/Los_Angeles

## Calendar feeds

After deployment:

/calendars/dublin-ca/all.ics

/calendars/dublin-ca/festivals.ics

/calendars/dublin-ca/vrat.ics

/calendars/dublin-ca/rahu-kalam.ics

## Generate locally

Requires Node.js 18+.

```bash
npm install
npm run generate
