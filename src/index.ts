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
