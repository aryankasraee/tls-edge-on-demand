import unittest

from ask import allowed


class AskTest(unittest.TestCase):
    tenants = {"acme.example", "school.example"}

    def test_listed_domain_is_allowed(self):
        self.assertTrue(allowed("acme.example", "allowlist", self.tenants))

    def test_case_and_whitespace_are_normalised(self):
        self.assertTrue(allowed("  ACME.example ", "allowlist", self.tenants))

    def test_unlisted_domain_is_refused(self):
        self.assertFalse(allowed("evil.example", "allowlist", self.tenants))

    def test_subdomain_of_a_listed_domain_is_not_implied(self):
        self.assertFalse(allowed("www.acme.example", "allowlist", self.tenants))

    def test_malformed_names_are_refused_even_in_open_mode(self):
        for bad in ["", "localhost", "a b.example", "-bad.example", "x" * 300 + ".example", "1.2.3.4"]:
            self.assertFalse(allowed(bad, "open", set()), bad)

    def test_open_mode_allows_any_wellformed_name(self):
        self.assertTrue(allowed("anything.example", "open", set()))

    def test_missing_file_fails_closed(self):
        import ask
        self.assertEqual(ask.load_tenants("/nonexistent/tenants.txt"), set())


if __name__ == "__main__":
    unittest.main()
