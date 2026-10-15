#!/usr/bin/env python3
"""Keep orange and red off words: they colour only the symbol beside primary text.

The kit's rule (docs/desktop.md, WorkbenchPageStyle.swift): orange never carries
text, 2.2:1 on a light card, and red is for recording and removal. A problem is
said in primary words beside an orange symbol, through WorkbenchNote in Voice
and PersonaNote in StageKit (#335).

This fails on any view in Sources/LocalVoice or Sources/StageKit, other than an
Image, whose own foregroundStyle or foregroundColor names orange, red or
Workbench.attention, including through a ternary. A Label or HStack whose orange
sits on its Image passes, because the style belongs to the Image. Comments and
string literals are not code. The few deliberate exceptions are named below.

    python3 scripts/check-attention-text.py          # the repository
    python3 scripts/check-attention-text.py DIR...   # other roots
"""
from pathlib import Path
import re
import sys

PROJECT = Path(__file__).resolve().parents[1]
FOLDERS = ('Sources/LocalVoice', 'Sources/StageKit')
STYLE = re.compile(r'\.\s*(?:foregroundStyle|foregroundColor)\s*\(')
ATTENTION = re.compile(r'\.\s*(?:orange|red|system(?:Orange|Red))\b|\bWorkbench\s*\.\s*attention\b')
# Views that draw no words.
WORDLESS = {'Image', 'Circle', 'Capsule', 'Ellipse', 'Rectangle', 'RoundedRectangle'}
# (file, the view's opening words, why it may stay).
ALLOWED = [
    ('Sources/LocalVoice/MeetingWorkspaceView.swift', 'Button("Finish meeting")',
     'red ends a recording, the recording exception'),
    ('Sources/StageKit/DemoScenesView.swift', 'Text("Hand missing',
     'temporary: hand authoring is being retired, and that change takes this line'),
    ('Sources/LocalVoice/WorkbenchQuickPanel.swift', 'Text(entry?.shortcut.enabled == true',
     'temporary: a conflicting shortcut still turns its keys orange; #335 decides between '
     'an orange symbol and saying it on hover only'),
]
COMMENTS = re.compile(r'/\*.*?\*/|//[^\n]*', re.DOTALL)
STRINGS = re.compile(r'"""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"')
CLOSERS = {')': '(', '}': '{', ']': '['}


def blank(match):
    return re.sub(r'[^\n]', ' ', match.group())


def code(text):
    """The text with every comment and string literal blanked, positions kept."""
    return STRINGS.sub(blank, COMMENTS.sub(blank, text))


def opener(text, close):
    """The position of the bracket that opens the one at `close`, or -1."""
    depth = 0
    for position in range(close, -1, -1):
        if text[position] in CLOSERS:
            depth += 1
        elif text[position] in '({[':
            depth -= 1
            if depth == 0:
                return position
    return -1


def closer(text, open_):
    depth = 0
    for position in range(open_, len(text)):
        if text[position] in '({[':
            depth += 1
        elif text[position] in CLOSERS:
            depth -= 1
            if depth == 0:
                return position
    return len(text)


def word_before(text, end):
    """(start, word) of the identifier ending at `end`, inclusive."""
    start = end
    while start >= 0 and (text[start].isalnum() or text[start] == '_'):
        start -= 1
    return start + 1, text[start + 1:end + 1]


def previous(text, position):
    while position >= 0 and text[position].isspace():
        position -= 1
    return position


def styled_view(text, dot):
    """(start, name) of the view a modifier at `dot` styles, walking back over its chain."""
    position = previous(text, dot - 1)
    while position >= 0:
        character = text[position]
        if character in CLOSERS:
            position = previous(text, opener(text, position) - 1)
        elif character == ':':
            # A trailing closure's label, as in `Label { … } icon: { … }`.
            start, _ = word_before(text, previous(text, position - 1))
            position = previous(text, start - 1)
        elif character.isalnum() or character == '_':
            start, name = word_before(text, position)
            before = previous(text, start - 1)
            if before >= 0 and text[before] == '.':
                position = previous(text, before - 1)
            else:
                return start, name
        else:
            return position + 1, ''
    return 0, ''


def coloured_words(root):
    """(relative path, line, view, opening) for every worded view styled orange or red."""
    found = []
    for folder in FOLDERS:
        for path in sorted((root / folder).glob('**/*.swift')):
            relative = path.relative_to(root).as_posix()
            original = path.read_text()
            text = code(original)
            for match in STYLE.finditer(text):
                arguments = text[match.end() - 1:closer(text, match.end() - 1) + 1]
                if not ATTENTION.search(arguments):
                    continue
                start, name = styled_view(text, match.start())
                if name in WORDLESS:
                    continue
                opening = ' '.join(original[start:match.start()].split())
                found.append((relative, text.count('\n', 0, match.start()) + 1, name or '?', opening))
    return found


def check(root):
    problems = []
    for relative, line, name, opening in coloured_words(root):
        if any(relative == path and opening.startswith(words) for path, words, _ in ALLOWED):
            continue
        problems.append(f'{relative}:{line}: {name} is styled orange or red; say it with '
                        f'WorkbenchNote or PersonaNote beside an orange symbol: {opening[:90]}')
    return problems


def main(arguments):
    roots = [Path(argument).resolve() for argument in arguments] or [PROJECT]
    problems = [problem for root in roots for problem in check(root)]
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print('Attention text: orange and red colour only symbols, with '
          f'{len(ALLOWED)} named exceptions')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
