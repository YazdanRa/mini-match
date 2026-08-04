from __future__ import annotations

import struct
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = ROOT / "apps" / "web"
SUPPORT_URL = "https://github.com/YazdanRa/mini-match/issues"
REPOSITORY_URL = "https://github.com/YazdanRa/mini-match"
EXPECTED_PAGES = {
    Path("index.html"),
    Path("privacy/index.html"),
}


class DocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []
        self.references: list[str] = []
        self.images: list[dict[str, str]] = []
        self.body_tags: list[str] = []
        self.text: list[str] = []
        self._in_body = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = {key: value or "" for key, value in attrs}
        if tag == "body":
            self._in_body = True
        elif self._in_body:
            self.body_tags.append(tag)

        if tag == "a" and "href" in attributes:
            self.links.append(attributes["href"])
            self.references.append(attributes["href"])
        elif tag == "link" and "href" in attributes:
            self.references.append(attributes["href"])
        elif tag == "img":
            self.images.append(attributes)
            if "src" in attributes:
                self.references.append(attributes["src"])

    def handle_endtag(self, tag: str) -> None:
        if tag == "body":
            self._in_body = False

    def handle_data(self, data: str) -> None:
        if self._in_body and (text := " ".join(data.split())):
            self.text.append(text)


def parse(relative_path: Path) -> DocumentParser:
    parser = DocumentParser()
    parser.feed((WEB_ROOT / relative_path).read_text(encoding="utf-8"))
    return parser


def png_dimensions(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG image: {path}")
    return struct.unpack(">II", header[16:24])


def internal_target(source: Path, href: str) -> Path | None:
    parsed = urlparse(href)
    if parsed.scheme or parsed.netloc or href.startswith("#"):
        return None

    target = (source.parent / parsed.path).resolve()
    target.relative_to(WEB_ROOT.resolve())
    if parsed.path.endswith("/"):
        target /= "index.html"
    return target


class WebsiteTests(unittest.TestCase):
    def test_exactly_two_html_pages_exist(self) -> None:
        pages = {path.relative_to(WEB_ROOT) for path in WEB_ROOT.rglob("*.html")}
        self.assertEqual(pages, EXPECTED_PAGES)

    def test_home_contains_the_requested_content_and_links(self) -> None:
        page = parse(Path("index.html"))

        self.assertEqual(page.text, ["Mini Match", "Coming soon…", "GitHub", "Privacy Policy"])
        self.assertEqual(page.body_tags, ["main", "img", "h1", "p", "nav", "a", "a"])
        self.assertEqual(page.links, [REPOSITORY_URL, "privacy/"])
        self.assertEqual(
            page.images,
            [{"class": "logo", "src": "assets/mini-match-logo.png", "alt": "Mini Match logo"}],
        )

    def test_website_logo_is_web_ready(self) -> None:
        app_icon = (
            ROOT
            / "apps/apple/MiniMatch/MiniMatch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        )
        website_logo = WEB_ROOT / "assets/mini-match-logo.png"

        self.assertEqual(png_dimensions(app_icon), (1024, 1024))
        self.assertEqual(png_dimensions(website_logo), (512, 512))
        self.assertLess(website_logo.stat().st_size, 500 * 1024)

    def test_privacy_page_has_support_and_home_links(self) -> None:
        page = parse(Path("privacy/index.html"))

        self.assertIn("Privacy Policy", page.text)
        self.assertIn("Effective August 4, 2026", page.text)
        self.assertIn(SUPPORT_URL, page.links)
        self.assertIn("../", page.links)

    def test_all_internal_references_resolve(self) -> None:
        for page_path in EXPECTED_PAGES:
            for reference in parse(page_path).references:
                with self.subTest(page=page_path, reference=reference):
                    target = internal_target(WEB_ROOT / page_path, reference)
                    if target is not None:
                        self.assertTrue(target.is_file(), f"Missing link target: {target}")


if __name__ == "__main__":
    unittest.main()
