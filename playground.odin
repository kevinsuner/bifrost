package main

import "core:testing"

HttpUrl :: struct {
    scheme:     string,
    host:       string,
    path:       string,
    raw_path:   string,
}

// Reports whether str contains any ASCII control character. 
_string_contains_control_character :: proc(str: string) -> bool {
    for _, idx in str {
        if str[idx] < ' ' || str[idx] == 0x7f {
            return true
        }
    }
    return false
}

// Provided url can be in the form of scheme:path, if so, return scheme and path,
// otherwise return empty string and path. Scheme must be ([a-zA-Z][a-zA-Z0-9+-.]*).
_extract_scheme_from_url :: proc(url: string) -> (scheme, path: string, ok: bool) {
    for char, idx in url {
        switch {
        case 'a' <= char && char <= 'z' || 'A' <= char && char <= 'Z':
            continue

        case '0' <= char && char <= '9' || char == '+' || char == '-' || char == '.': 
            // [0-9+-.] found at the beginning, no scheme found
            if idx == 0 {
                return "", url, true
            }
            
        case char == ':':
            if idx == 0 {
                // colon found at the beginning, missing protocol scheme
                return "", "", false
            }
            return url[:idx], url[idx+1:], true

        case:
            // invalid character found, no valid scheme found
            return "", url, true
        }
    }
    return "", url, true
}

@(test)
test_string_contains_control_character :: proc(t: ^testing.T) {
    ok := _string_contains_control_character("http://foo.com/?foo\nbar")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http\r://foo.com/")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo\x7f.com/")
    testing.expect_value(t, ok, true)

    ok = _string_contains_control_character("http://foo.com/?foo&bar")
    testing.expect_value(t, ok, false)

    ok = _string_contains_control_character("http://foo.com/") 
    testing.expect_value(t, ok, false)
}

@(test)
test_extract_scheme_from_url :: proc(t: ^testing.T) {
    scheme, url, ok := _extract_scheme_from_url("0http://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "0http://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("+http://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "+http://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("-http://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "-http://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url(".http://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, ".http://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "")
    testing.expect_value(t, ok, false)

    scheme, url, ok = _extract_scheme_from_url(" http://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, " http://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("ht tp://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "ht tp://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("ht_tp://foo.com")
    testing.expect_value(t, scheme, "")
    testing.expect_value(t, url, "ht_tp://foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("http://foo.com")
    testing.expect_value(t, scheme, "http")
    testing.expect_value(t, url, "//foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("https://foo.com")
    testing.expect_value(t, scheme, "https")
    testing.expect_value(t, url, "//foo.com")
    testing.expect_value(t, ok, true)

    scheme, url, ok = _extract_scheme_from_url("ssh://foo@bar")
    testing.expect_value(t, scheme, "ssh")
    testing.expect_value(t, url, "//foo@bar")
    testing.expect_value(t, ok, true)
}























