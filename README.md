# GlueX Web Snapshot

This repository contains a small shell script that mirrors selected GlueX web pages into a static site that can be browsed offline.

## What it does

The main entry point is [snapshot.sh](snapshot.sh). It uses `wget` to recursively copy the URLs listed in `urls.txt` into a local output directory, rewrites links for offline browsing, and can optionally build a client-side search index.

The repository also includes [run.sh](run.sh), which is a convenience wrapper that runs the snapshot with the default cookie file.

## Requirements

You need:

1. `bash`
2. `wget`
3. `sed`
4. `tee`

If you enable the optional search index, you also need `node` and `npx`.

## How to make a snapshot

1. Put the pages you want to mirror in `urls.txt`. One URL per line is enough.
2. If you need to access private pages, provide a Netscape-format cookie file such as `cookies.txt`.
3. Run the snapshot script:

```bash
COOKIE_JAR=./cookies.txt ENABLE_PAGEFIND=1 OBEY_ROBOTS=1 ./snapshot.sh urls.txt site
```

By default, the mirrored site is written into `site/`.

## Where to set the username and password

If the site requires HTTP basic authentication, edit these two lines in [snapshot.sh](snapshot.sh):

```bash
--user=username
--password=password
```

They are inside the `WGET_ARGS` array in [snapshot.sh](snapshot.sh). Replace those placeholder values with the correct username and password for your account.

If you are logging in through a web session instead of basic auth, update or replace the cookie file passed through `COOKIE_JAR` instead.

## Output

The script creates:

1. A mirrored copy of the requested pages under the output directory.
2. A log file for each URL under `site/`.
3. A small landing page at `site/index.html`.

## Make a Docker image for offline use

After you have built the snapshot into `site/`, you can package it into a Docker image and move that image to another machine:

```bash
# Build the offline image from the mirrored site
docker build -t halld-offline .

# Save it as a portable archive
docker save halld-offline | gzip > halld-offline.tar.gz

# On the offline machine, load and run it
docker load < halld-offline.tar.gz
docker run -d -p 8080:80 halld-offline
```

Then browse the mirrored site at `http://localhost:8080/`.

The image is built from [Dockerfile](Dockerfile), which serves the contents of `site/` with nginx.

## Notes

The script is configured to respect `robots.txt` by default. If you have permission to crawl a site and need to override that behavior, set `OBEY_ROBOTS=0`.

The script also skips some dynamic endpoints such as login, edit, and search URLs because they do not usually work well in an offline mirror.