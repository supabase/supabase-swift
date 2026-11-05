#!/usr/bin/env bash
# Usage: check-isolation-coverage.sh <Module> <test-file>
#
# Fails when a public API of Sources/<Module> that a main-actor caller must `await` has no call in
# <test-file>. That file proves each such API compiles from a main-actor call site.
#
# The check covers:
# - public async functions, including the nonisolated ones,
# - public async properties (`{ get async }`),
# - every public function and property declared in a public actor or in an extension of it, since
#   a main-actor caller reaches those with `await` too.
#
# It matches by name only: a new overload, or a new member whose name the file already calls on
# another type, passes without a call, so add those calls by hand. It does not see async
# initializers.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "usage: $0 <Module> <test-file>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

module=$1
test_file=$2
sources=Sources/$module

members=$(
  find "$sources" -name '*.swift' -print0 \
    | xargs -0 perl -0777 -e '
      my $mods = qr/(?:(?:static|mutating|nonisolated|final|override)\s+)*/;
      my $params = qr/(\((?:[^()]++|(?-1))*\))/;
      my (%files, %actors);
      for my $file (@ARGV) {
        open my $fh, "<", $file or die "$file: $!";
        local $/;
        my $src = <$fh>;
        $src =~ s{^\s*//.*$}{}mg;
        $files{$file} = $src;
        $actors{$1} = 1 while $src =~ /\bpublic\s+(?:final\s+)?actor\s+(\w+)/g;
      }
      my $actor = join "|", map { quotemeta } keys %actors;
      for my $src (values %files) {
        print "func $1\n" while $src =~ /\bpublic\s+${mods}func\s+(\w+)\s*(?:<[^>]*>)?\s*$params\s*async\b/g;
        print "var $1\n" while $src =~ /\bpublic\s+${mods}var\s+(\w+)\s*:[^{]*\{\s*get\s+async\b/g;
        next unless $actor;
        while ($src =~ /\b(?:actor|extension)\s+(?:$actor)\b[^{]*(\{(?:[^{}]++|(?-1))*\})/g) {
          my $body = $1;
          while ($body =~ /\bpublic\s+((?:(?:static|final|override|nonisolated)\s+)*)(func|var|let)\s+(\w+)/g) {
            next if $1 =~ /nonisolated/;
            print(($2 eq "func" ? "func" : "var") . " $3\n");
          }
        }
      }
    ' \
    | sort -u
)

missing=$(
  echo "$members" | while read -r kind name; do
    if [ "$kind" = func ]; then
      grep -qF ".$name(" "$test_file" || echo "$name()"
    else
      grep -qE "\.$name\b" "$test_file" || echo "$name"
    fi
  done
)

if [ -n "$missing" ]; then
  echo "Public $module APIs that a main-actor caller awaits, with no call in $test_file:" >&2
  echo "$missing" >&2
  exit 1
fi

echo "Every public $module API that a main-actor caller awaits is called in $test_file."
