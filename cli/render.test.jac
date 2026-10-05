"""Rendering helpers produce clean text when color is off."""

test "plain output has no escape codes" {
    set_color(False);
    assert hex_fg("hi", "#ff0000") == "hi";
    assert bold("x") == "x";
    assert strip_ansi("\x1b[1mbold\x1b[0m") == "bold";
    assert pad("ab", 5) == "ab   ";
    assert truncate("abcdefgh", 5) == "abcd…";
    assert grade_bar(50.0, 10, "#000000") == "█████░░░░░";
    assert grade_bar(None, 3, "#000000") == "···";
}

test "colored output is padded by visible width" {
    set_color(True);
    colored = hex_fg("EECS", "#2563eb");
    assert colored != "EECS";
    assert strip_ansi(colored) == "EECS";
    assert len(strip_ansi(pad(colored, 8))) == 8;
    set_color(False);
}
