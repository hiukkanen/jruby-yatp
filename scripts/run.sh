#!/usr/bin/env bash
# Käyttö: JRUBY_VERSION=9.4.12.0 NOKOGIRI_VERSION=1.18.9 JRUBY_RACK_VERSION=1.2.0 TOMCAT_VERSION=9.0.98 ./scripts/run.sh
set -euo pipefail
: "${JRUBY_VERSION:?}" "${NOKOGIRI_VERSION:?}" "${JRUBY_RACK_VERSION:?}" "${TOMCAT_VERSION:?}"
PORT="${PORT:-8080}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.cache"
WORK="$ROOT/work/jruby-$JRUBY_VERSION-noko-$NOKOGIRI_VERSION-rack-$JRUBY_RACK_VERSION-tc-$TOMCAT_VERSION"
MAVEN=https://repo1.maven.org/maven2
TC_MAJOR="${TOMCAT_VERSION%%.*}"

mkdir -p "$CACHE"; rm -rf "$WORK"; mkdir -p "$WORK"

fetch() { # url -> polku cacheen
  local f="$CACHE/$(basename "$1")"
  [ -s "$f" ] || curl -fsSL --retry 3 -o "$f" "$1"
  echo "$f"
}

echo "::group::Lataukset"
JRUBY_JAR=$(fetch "$MAVEN/org/jruby/jruby-complete/$JRUBY_VERSION/jruby-complete-$JRUBY_VERSION.jar")
RACK_JAR=$(fetch "$MAVEN/org/jruby/rack/jruby-rack/$JRUBY_RACK_VERSION/jruby-rack-$JRUBY_RACK_VERSION.jar")
TC_TGZ=$(fetch "https://archive.apache.org/dist/tomcat/tomcat-$TC_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz")
echo "::endgroup::"

echo "::group::WAR:n rakennus"
WAR="$WORK/war"
mkdir -p "$WAR/WEB-INF/lib"
cp "$ROOT/app/web.xml" "$ROOT/app/config.ru" "$WAR/WEB-INF/"
cp "$JRUBY_JAR" "$WAR/WEB-INF/lib/jruby-complete.jar"
cp "$RACK_JAR"  "$WAR/WEB-INF/lib/jruby-rack.jar"
java -jar "$JRUBY_JAR" -S gem install nokogiri -v "$NOKOGIRI_VERSION" \
  --install-dir "$WAR/WEB-INF/gems" --no-document
java -jar "$JRUBY_JAR" -S gem install rack -v '~> 2.2' \
  --install-dir "$WAR/WEB-INF/gems" --no-document
(cd "$WAR" && jar cf "$WORK/ROOT.war" .)
echo "::endgroup::"

TC="$WORK/tomcat"
mkdir -p "$TC"; tar xzf "$TC_TGZ" -C "$TC" --strip-components=1
rm -rf "$TC"/webapps/*
cp "$WORK/ROOT.war" "$TC/webapps/ROOT.war"
sed -i "s/port=\"8080\"/port=\"$PORT\"/" "$TC/conf/server.xml"

export CATALINA_OPTS="${CATALINA_OPTS:--Xmx512m}"
export CATALINA_PID="$WORK/tomcat.pid"

dump_logs() {
  echo "::group::Tomcat-lokit"
  tail -n 200 "$TC"/logs/catalina.out "$TC"/logs/localhost.*.log 2>/dev/null || true
  echo "::endgroup::"
}
cleanup() { "$TC/bin/catalina.sh" stop 5 -force >/dev/null 2>&1 || true; }
trap 'rc=$?; [ $rc -ne 0 ] && dump_logs; cleanup; exit $rc' EXIT

"$TC/bin/catalina.sh" start

echo "Odotetaan sovelluksen käynnistymistä..."
for i in $(seq 1 90); do
  if curl -fs "http://localhost:$PORT/health" -o "$WORK/health.json"; then break; fi
  [ "$i" -eq 90 ] && { echo "FAIL: sovellus ei käynnistynyt 180 s:ssa"; exit 1; }
  sleep 2
done
echo "Käynnistyi ~$((i*2)) s:ssa"; cat "$WORK/health.json"; echo

curl -fs "http://localhost:$PORT/nokogiri" -o "$WORK/nokogiri.json" || { echo "FAIL: /nokogiri"; cat "$WORK/nokogiri.json"; exit 1; }
cat "$WORK/nokogiri.json"; echo

jq -e --arg n "$NOKOGIRI_VERSION" '.versions.nokogiri == $n and (.checks | all(.[]; . == true))' "$WORK/nokogiri.json" >/dev/null \
  || { echo "FAIL: Nokogiri-versio tai tarkistukset eivät täsmää"; exit 1; }
jq -e --arg r "$JRUBY_RACK_VERSION" '.versions.jruby_rack == $r' "$WORK/nokogiri.json" >/dev/null \
  || echo "VAROITUS: jruby-rack-versio ei täsmää (tai ei raportoitu)"
echo "OK: jruby=$JRUBY_VERSION nokogiri=$NOKOGIRI_VERSION jruby-rack=$JRUBY_RACK_VERSION tomcat=$TOMCAT_VERSION"
