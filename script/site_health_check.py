#!/usr/bin/env python3
"""Checks the live store from the outside: pages up, every old-link redirect,
the .art forwards, TLS certificates and the Merchant Center feed.

Run by .github/workflows/site-health-check.yml. Exits non-zero when anything
fails, which fails the workflow run, and GitHub then emails the repo owner.

    python script/site_health_check.py   # needs PyYAML
"""
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

import yaml

BASE = "https://www.everfluorescent.com"
PAGES = ["/", "/products", "/products/winged-cat-fleece-hoodie", "/gallery", "/cart", "/sitemap.xml", "/up"]
SLOW_SECONDS = 8
OLD_LINK = "/products/winged-cat-fleece-hoodie-mens-fleece-full-zip-hoodie-model-h60"
OLD_LINK_LANDS_ON = BASE + "/products/winged-cat-fleece-hoodie"
ART_HOSTS = ["everfluorescent.art", "www.everfluorescent.art", "shop.everfluorescent.art"]
CERT_HOSTS = ["www.everfluorescent.com", "everfluorescent.art"]
CERT_MIN_DAYS = 14
FEED_MIN_ITEMS = 250
FEED_REQUIRED = ["id", "title", "link", "image_link", "price", "availability"]
G = "{http://base.google.com/ns/1.0}"
HEADERS = {"User-Agent": "everfluorescent-health-check (+github actions)"}

failures = []
summary = []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


no_redirect = urllib.request.build_opener(NoRedirect)
follow = urllib.request.build_opener()


def fetch(url, opener=follow, attempts=2):
    """Returns (status, location_or_final_url, body, seconds); status 0 on network error."""
    for attempt in range(attempts):
        started = time.monotonic()
        try:
            with opener.open(urllib.request.Request(url, headers=HEADERS), timeout=30) as resp:
                return resp.status, resp.geturl(), resp.read(), time.monotonic() - started
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Location", ""), b"", time.monotonic() - started
        except (urllib.error.URLError, socket.timeout, ConnectionError) as e:
            if attempt == attempts - 1:
                return 0, str(e), b"", time.monotonic() - started
            time.sleep(5)


def fail(section, message):
    failures.append(f"{section}: {message}")


def check_pages():
    bad = 0
    for path in PAGES:
        status, _, _, seconds = fetch(BASE + path)
        if status != 200:
            bad += 1
            fail("Site up", f"{path} returned {status or 'no response'}")
        elif seconds > SLOW_SECONDS:
            bad += 1
            fail("Site up", f"{path} took {seconds:.1f}s")
    summary.append(f"Site up: {len(PAGES) - bad}/{len(PAGES)} pages OK")


def legacy_redirects():
    table = yaml.safe_load(open("config/legacy_redirects.yml", encoding="utf-8"))
    prefixes = {"products": "/products/", "listings": "/listing/", "collections": "/collections/", "paths": ""}
    for section, prefix in prefixes.items():
        for key, target in (table.get(section) or {}).items():
            yield prefix + str(key), target


def check_redirects():
    entries = list(legacy_redirects())
    ok = 0
    for old, target in entries:
        status, location, _, _ = fetch(BASE + old, opener=no_redirect)
        location = location.removeprefix(BASE)
        if status == 301 and location == target:
            ok += 1
        else:
            fail("Redirects", f"{old} -> {status or 'no response'} {location} (expected 301 {target})")
    targets = sorted({t for _, t in entries})
    live = 0
    for target in targets:
        status, _, _, _ = fetch(BASE + target)
        if status == 200:
            live += 1
        else:
            fail("Redirects", f"target {target} returned {status or 'no response'}")
    summary.append(f"Redirects: {ok}/{len(entries)} correct, {live}/{len(targets)} targets live")


def check_art_forwards():
    ok = 0
    for host in ART_HOSTS:
        for scheme in ("http", "https"):
            url = f"{scheme}://{host}{OLD_LINK}"
            status, final, _, _ = fetch(url)
            if status == 200 and final.split("?")[0] == OLD_LINK_LANDS_ON:
                ok += 1
            else:
                fail("Old domains", f"{url} ended at {status or 'no response'} {final}")
    summary.append(f"Old domains: {ok}/{len(ART_HOSTS) * 2} forwards land on the product")


def check_certs():
    parts = []
    for host in CERT_HOSTS:
        try:
            with socket.create_connection((host, 443), timeout=20) as sock:
                with ssl.create_default_context().wrap_socket(sock, server_hostname=host) as tls:
                    expires = ssl.cert_time_to_seconds(tls.getpeercert()["notAfter"])
        except (OSError, ssl.SSLError) as e:
            fail("Certificates", f"{host}: {e}")
            parts.append(f"{host} invalid")
            continue
        days = int((expires - time.time()) // 86400)
        parts.append(f"{host} {days}d")
        if days < CERT_MIN_DAYS:
            fail("Certificates", f"{host} expires in {days} days")
    summary.append("Certificates: " + ", ".join(parts))


def check_feed():
    status, _, body, _ = fetch(BASE + "/feeds/google.xml")
    if status != 200:
        fail("Feed", f"/feeds/google.xml returned {status or 'no response'}")
        summary.append("Feed: unavailable")
        return
    try:
        items = ET.fromstring(body).find("channel").findall("item")
    except (ET.ParseError, AttributeError) as e:
        fail("Feed", f"not valid RSS: {e}")
        summary.append("Feed: invalid")
        return
    ids = [i.findtext(G + "id") for i in items]
    if len(items) < FEED_MIN_ITEMS:
        fail("Feed", f"only {len(items)} items (expected at least {FEED_MIN_ITEMS})")
    if len(ids) != len(set(ids)):
        fail("Feed", f"{len(ids) - len(set(ids))} duplicate ids")
    incomplete = sum(1 for i in items if any(not (i.findtext(G + f) or "").strip() for f in FEED_REQUIRED))
    if incomplete:
        fail("Feed", f"{incomplete} items missing a required field")
    summary.append(f"Feed: {len(items)} items")


def main():
    for check in (check_pages, check_redirects, check_art_forwards, check_certs, check_feed):
        check()

    report = ["## Store health check", ""] + [f"- {line}" for line in summary]
    if failures:
        report += ["", f"### {len(failures)} problem(s)", ""] + [f"- {f}" for f in failures]
    print("\n".join(report))
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as out:
            out.write("\n".join(report) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
