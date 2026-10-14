import json
from pathlib import Path
import sys
import tempfile
import unittest
from urllib.error import URLError

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "helpers"))
import weather

PLACE = {"name": "Chișinău", "region": "Moldova", "latitude": 47.009, "longitude": 28.8594}
FORECAST = {
    "current": {"temperature_2m": 17.6, "apparent_temperature": 14.8, "weather_code": 0, "is_day": 0},
    "daily": {"time": ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03"], "weather_code": [0, 2, 61, 95],
              "temperature_2m_max": [20.4, 19.6, 16, 14.2], "temperature_2m_min": [10, 8.4, 9, 5],
              "precipitation_probability_max": [0, 5, 80, 60]},
}


class ParseTests(unittest.TestCase):
    def test_forecast_is_reduced_to_current_and_next_three_days(self):
        result = weather.parse(FORECAST)
        self.assertEqual(result["current"], {"temperature": 18, "feelsLike": 15, "label": "Clear", "icon": "moon", "high": 20, "low": 10})
        self.assertEqual([day["date"] for day in result["days"]], ["2026-10-01", "2026-10-02", "2026-10-03"])
        self.assertEqual([(day["icon"], day["label"]) for day in result["days"]], [("cloud-sun", "Partly cloudy"), ("rain", "Light rain"), ("storm", "Thunderstorm")])

    def test_unknown_codes_and_missing_values_degrade_gracefully(self):
        data = {"current": {"weather_code": 1234, "temperature_2m": None}, "daily": {}}
        result = weather.parse(data)
        self.assertEqual((result["current"]["label"], result["current"]["icon"], result["current"]["temperature"]), ("Unknown", "cloud", None))
        self.assertEqual(result["days"], [])
        with self.assertRaises(ValueError):
            weather.parse({"current": {}})

    def test_every_icon_exists(self):
        for label, day, night in weather.CODES.values():
            for icon in (day, night):
                with self.subTest(icon=icon):
                    self.assertTrue((ROOT / "assets/icons" / (icon + ".svg")).is_file())
                    self.assertIn(json.dumps(icon) + ":", (ROOT / "core/icons.js").read_text())


class RequestTests(unittest.TestCase):
    def test_only_open_meteo_https_addresses_are_allowed(self):
        self.assertTrue(weather._url("https://api.open-meteo.com/v1/forecast?x=1"))
        for url in ("http://api.open-meteo.com/v1/forecast", "https://evil.example/v1", "https://api.open-meteo.com:8443/v1",
                    "https://user@api.open-meteo.com/v1", "file:///etc/passwd"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                weather._url(url)

    def test_search_validates_the_query_and_cleans_results(self):
        for query in ("", "a", " b ", "x" * 101, None):
            with self.subTest(query=query), self.assertRaises(ValueError):
                weather.search(query, fetch=lambda url: {})
        urls = []
        def fetch(url):
            urls.append(url)
            return {"results": [{"name": "Chișinău", "admin1": "Chișinău Municipality", "country": "Moldova", "latitude": 47.00902, "longitude": 28.85939},
                                {"name": "Paris", "country": "France", "latitude": 48.85, "longitude": 2.35},
                                {"name": "Broken", "latitude": 200, "longitude": 0}, "junk"]}
        results = weather.search(" Chis ", fetch=fetch)
        self.assertIn("name=Chis&", urls[0])
        self.assertEqual(results, [{"name": "Chișinău", "region": "Chișinău Municipality, Moldova", "latitude": 47.009, "longitude": 28.8594},
                                   {"name": "Paris", "region": "France", "latitude": 48.85, "longitude": 2.35}])
        self.assertEqual(weather.search("zzzz", fetch=lambda url: {}), [])

    def test_locations_are_validated(self):
        self.assertEqual(weather.validate_location({}), {})
        self.assertEqual(weather.validate_location(PLACE), PLACE)
        for value in ([], {"name": "x"}, {**PLACE, "latitude": 91}, {**PLACE, "longitude": True}, {**PLACE, "name": ""},
                      {**PLACE, "extra": 1}, {**PLACE, "latitude": float("nan")}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                weather.validate_location(value)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "cache" / "weather.json"
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def fetch(self, url):
        self.calls.append(url)
        return FORECAST

    def offline(self, url):
        self.calls.append(url)
        raise URLError("offline")

    def test_forecast_is_cached_for_thirty_minutes_per_place_and_units(self):
        first = weather.forecast(PLACE, "metric", self.cache, fetch=self.fetch, now=lambda: 1000)
        self.assertEqual((first["fetched"], first["stale"], first["location"], first["units"]), (1000, False, PLACE, "metric"))
        self.assertNotIn("temperature_unit", self.calls[0])
        weather.forecast(PLACE, "metric", self.cache, fetch=self.fetch, now=lambda: 1000 + weather.FRESH - 1)
        self.assertEqual(len(self.calls), 1)
        weather.forecast(PLACE, "metric", self.cache, fetch=self.fetch, now=lambda: 1000 + weather.FRESH + 1)
        self.assertEqual(len(self.calls), 2)
        weather.forecast(PLACE, "imperial", self.cache, fetch=self.fetch, now=lambda: 5000)
        self.assertIn("temperature_unit=fahrenheit", self.calls[2])

    def test_refresh_only_skips_a_copy_older_than_a_minute(self):
        weather.forecast(PLACE, "metric", self.cache, fetch=self.fetch, now=lambda: 1000)
        weather.forecast(PLACE, "metric", self.cache, refresh=True, fetch=self.fetch, now=lambda: 1030)
        self.assertEqual(len(self.calls), 1)
        weather.forecast(PLACE, "metric", self.cache, refresh=True, fetch=self.fetch, now=lambda: 1100)
        self.assertEqual(len(self.calls), 2)

    def test_offline_falls_back_to_the_last_forecast(self):
        with self.assertRaises(URLError):
            weather.forecast(PLACE, "metric", self.cache, fetch=self.offline, now=lambda: 1000)
        weather.forecast(PLACE, "metric", self.cache, fetch=self.fetch, now=lambda: 1000)
        stale = weather.forecast(PLACE, "metric", self.cache, fetch=self.offline, now=lambda: 9000)
        self.assertEqual((stale["stale"], stale["fetched"], stale["warning"]), (True, 1000, "Weather is unavailable offline."))
        self.cache.write_text("not json")
        with self.assertRaises(URLError):
            weather.forecast(PLACE, "metric", self.cache, fetch=self.offline, now=lambda: 9000)

    def test_forecast_requires_a_city_and_known_units(self):
        with self.assertRaises(ValueError):
            weather.forecast({}, "metric", self.cache, fetch=self.fetch)
        with self.assertRaises(ValueError):
            weather.forecast(PLACE, "kelvin", self.cache, fetch=self.fetch)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
