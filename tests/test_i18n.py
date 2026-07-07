from i18n import (
    COUNTRY_KEYS,
    DEFAULT_LANGUAGE,
    SUPPORTED_LANGUAGES,
    TRANSLATIONS,
    country_label,
    localized_country_groups,
    normalize_language,
    translate,
)


def test_translation_catalogs_have_identical_keys() -> None:
    english_keys = set(TRANSLATIONS["en"])
    greek_keys = set(TRANSLATIONS["el"])

    assert english_keys == greek_keys


def test_supported_languages_and_fallback() -> None:
    assert SUPPORTED_LANGUAGES == ("en", "el")
    assert normalize_language("en") == "en"
    assert normalize_language("el") == "el"
    assert normalize_language("fr") == DEFAULT_LANGUAGE
    assert normalize_language(None) == DEFAULT_LANGUAGE


def test_country_catalog_is_complete_in_both_languages() -> None:
    for language in SUPPORTED_LANGUAGES:
        groups = localized_country_groups(language)
        flattened_codes = [code for _, countries in groups for code, _ in countries]

        assert set(flattened_codes) == set(COUNTRY_KEYS)
        assert all(country_label(language, code) != code.upper() for code in COUNTRY_KEYS)


def test_parameterized_translation() -> None:
    assert translate("en", "seconds_ago", seconds=3) == "3s ago"
    assert translate("el", "seconds_ago", seconds=3) == "πριν από 3s"
