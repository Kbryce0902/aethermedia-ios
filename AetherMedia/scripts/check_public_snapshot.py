#!/usr/bin/env python3
"""Check the publishable snapshot without printing candidate credential values."""
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SKIP = {'.git', '.build', 'build', 'DerivedData', '__pycache__', 'xcuserdata'}
PATTERNS = {
    'private_key': r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'github_token': r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
    'openai_key': r'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{30,}',
    'aws_access_key': r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'google_api_key': r'\bAIza[A-Za-z0-9_-]{35}\b',
    'slack_token': r'\bxox[baprs]-[A-Za-z0-9-]{20,}',
    'jwt': r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}',
    'url_credentials': r'https?://[^\s/"<>:]+:[^\s/"<>]+@',
}
INLINE = re.compile(r'''(?ix)(?:access_?token|refresh_?token|client_?secret|api_?key|password)["']?\s*[:=]\s*["']([A-Za-z0-9_./+\-=]{24,})["']''')
FORBIDDEN_SUFFIXES = {'.p12', '.pfx', '.mobileprovision', '.key', '.ipa', '.log'}
FORBIDDEN_NAMES = {'pending-grant.json', 'authorize.json', 'report.json', 'credentials.json'}


def main():
    findings = []
    files = 0
    for path in sorted(ROOT.rglob('*')):
        relative = path.relative_to(ROOT)
        if not path.is_file() or any(part in SKIP for part in relative.parts):
            continue
        files += 1
        if (path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name in FORBIDDEN_NAMES
                or path.name == '.env' or path.name.startswith('.env.')):
            findings.append({'file': str(relative), 'category': 'private_or_build_file'})
        try:
            content = path.read_text()
        except UnicodeDecodeError:
            continue
        for category, expression in PATTERNS.items():
            for match in re.finditer(expression, content):
                findings.append({'file': str(relative), 'line': content.count('\n', 0, match.start()) + 1,
                                 'category': category})
        for match in INLINE.finditer(content):
            value = match.group(1)
            synthetic = 'Tests' in relative.parts and re.search(r'(?i)mock|test|fake|placeholder|do_not_use', value)
            if not synthetic:
                findings.append({'file': str(relative), 'line': content.count('\n', 0, match.start()) + 1,
                                 'category': 'embedded_credential_literal'})
    print(json.dumps({'files_checked': files, 'credential_findings': findings,
                      'result': 'failed' if findings else 'passed'}, indent=2))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
