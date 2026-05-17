# requirements:
# wmill
# requests

import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
from typing import Callable, Optional

import requests
import wmill

TERMINAL_STATUSES = {"success", "failure", "error", "killed", "declined", "blocked"}

EMBED_BLUE = 0x3498DB
EMBED_GREEN = 0x2ECC71
EMBED_RED = 0xE74C3C
EMBED_YELLOW = 0xF1C40F


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main(
    repo_ssh_url: str,
    repo_owner: str,
    repo_name: str,
    forgejo_base_url: str,
    woodpecker_base_url: str,
    branch: str = "main",
    deploy_key_variable: str = "u/me/forgejo_deploy_key",
    discord_webhook_variable: str = "u/me/discord_webhook",
    woodpecker_token_variable: str = "u/me/woodpecker_token",
    known_hosts_variable: str = "",
    git_user_name: str = "NightsEdge Autoupdate",
    git_user_email: str = "nightsedge-autoupdate@hydranet",
    build_timeout_seconds: int = 28800,  # 8h = 8 * 60 * 60
    pipeline_poll_interval: int = 60,
    pipeline_discover_timeout: int = 180,
):
    log(f"NightsEdge autoupdate starting for {repo_owner}/{repo_name} on branch {branch}")

    deploy_key = wmill.get_variable(deploy_key_variable)
    webhook_url = wmill.get_variable(discord_webhook_variable)
    woodpecker_token = wmill.get_variable(woodpecker_token_variable)
    known_hosts = wmill.get_variable(known_hosts_variable) if known_hosts_variable else ""

    discord = DiscordWebhook(webhook_url)
    woodpecker = WoodpeckerClient(woodpecker_base_url, woodpecker_token, repo_owner, repo_name)

    workdir = tempfile.mkdtemp(prefix="nightsedge-")
    key_path = os.path.join(workdir, "id_deploy")
    kh_path = os.path.join(workdir, "known_hosts")
    repo_dir = os.path.join(workdir, "repo")

    stage = {"name": "init"}

    try:
        with open(key_path, "w") as f:
            f.write(deploy_key.rstrip("\n") + "\n")
        os.chmod(key_path, stat.S_IRUSR | stat.S_IWUSR)

        if known_hosts:
            with open(kh_path, "w") as f:
                f.write(known_hosts.rstrip("\n") + "\n")
            host_opts = f"-o UserKnownHostsFile={kh_path} -o StrictHostKeyChecking=yes"
            log("SSH: strict host key checking enabled")
        else:
            host_opts = "-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null"
            log("SSH: TOFU mode (no known_hosts provided)")

        env = os.environ.copy()
        env["GIT_SSH_COMMAND"] = f"ssh -i {key_path} -o IdentitiesOnly=yes {host_opts}"

        def run(cmd, **kw):
            return subprocess.run(
                cmd, check=True, capture_output=True, text=True, env=env, **kw
            )

        stage["name"] = "clone"
        log(f"Cloning {repo_ssh_url} ({branch})")
        run(["git", "clone", "--branch", branch, repo_ssh_url, repo_dir])
        run(["git", "-C", repo_dir, "config", "user.name", git_user_name])
        run(["git", "-C", repo_dir, "config", "user.email", git_user_email])

        before_sha = run(["git", "-C", repo_dir, "rev-parse", "HEAD"]).stdout.strip()
        before_version = read_version(repo_dir)
        log(f"Cloned at {before_sha[:10]}, current VERSION={before_version}")

        stage["name"] = "check_and_update"
        log("Running scripts/check-and-update-version.sh --write --commit")
        run(["scripts/check-and-update-version.sh", "--write", "--commit"], cwd=repo_dir)

        after_sha = run(["git", "-C", repo_dir, "rev-parse", "HEAD"]).stdout.strip()
        after_version = read_version(repo_dir)

        if before_sha == after_sha:
            log(f"No version change (still {before_version}); posting quiet message")
            discord.post(
                content=(
                    f"NightsEdge autoupdate ran — no new Firefox release "
                    f"(staying on `{before_version}`)."
                )
            )
            return {"status": "no_change", "version": before_version}

        log(f"Version bumped {before_version} -> {after_version}, new commit {after_sha[:10]}")

        stage["name"] = "push"
        log(f"Pushing to origin/{branch}")
        run(["git", "-C", repo_dir, "push", "origin", branch])
        log("Push complete")

        commit_subject = run(
            ["git", "-C", repo_dir, "log", "-1", "--pretty=%s"]
        ).stdout.strip()
        commit_url = f"{forgejo_base_url.rstrip('/')}/{repo_owner}/{repo_name}/commit/{after_sha}"

        push_embed = {
            "title": f"NightsEdge update: {before_version} → {after_version}",
            "url": commit_url,
            "color": EMBED_BLUE,
            "fields": [
                {"name": "Previous", "value": f"`{before_version}`", "inline": True},
                {"name": "New", "value": f"`{after_version}`", "inline": True},
                {"name": "Commit", "value": f"[`{after_sha[:10]}`]({commit_url})", "inline": True},
                {"name": "Message", "value": commit_subject, "inline": False},
                {"name": "Build", "value": "_waiting for Woodpecker…_", "inline": False},
            ],
        }
        push_msg_id = discord.post_embed(push_embed)
        log(f"Posted push embed (Discord msg {push_msg_id})")

        stage["name"] = "discover_push_pipeline"
        log(f"Looking for Woodpecker pipeline matching commit {after_sha[:10]} (up to {pipeline_discover_timeout}s)")
        push_pipeline = woodpecker.find_pipeline(
            lambda p: p.get("commit") == after_sha and (p.get("event") or "") != "tag",
            timeout=pipeline_discover_timeout,
        )
        if push_pipeline is None:
            log("No push pipeline found within discover timeout")
            push_embed["color"] = EMBED_YELLOW
            push_embed["fields"][-1] = {
                "name": "Build",
                "value": "_no Woodpecker pipeline appeared — check manually_",
                "inline": False,
            }
            discord.edit(push_msg_id, embed=push_embed)
            return {"status": "pushed_no_pipeline", "commit": after_sha}

        push_pipeline_url = woodpecker.pipeline_url(push_pipeline["number"])
        log(f"Found push pipeline #{push_pipeline['number']} ({push_pipeline_url})")
        push_embed["fields"][-1] = {
            "name": "Build",
            "value": f"[#{push_pipeline['number']}]({push_pipeline_url}) — running…",
            "inline": False,
        }
        discord.edit(push_msg_id, embed=push_embed)

        stage["name"] = "wait_push_build"
        log(f"Waiting for pipeline #{push_pipeline['number']} (poll every {pipeline_poll_interval}s, timeout {build_timeout_seconds}s)")
        push_final = woodpecker.wait_for_pipeline(
            push_pipeline["number"],
            timeout=build_timeout_seconds,
            interval=pipeline_poll_interval,
            label=f"push#{push_pipeline['number']}",
        )
        log(f"Push pipeline #{push_pipeline['number']} ended: {push_final['status']}")

        if push_final["status"] != "success":
            push_embed["color"] = EMBED_RED
            push_embed["fields"][-1] = {
                "name": "Build",
                "value": f"[#{push_pipeline['number']}]({push_pipeline_url}) — **{push_final['status']}**",
                "inline": False,
            }
            discord.edit(push_msg_id, embed=push_embed)
            discord.post_embed({
                "title": f"❌ Build failed for {after_version}",
                "url": push_pipeline_url,
                "color": EMBED_RED,
                "description": (
                    f"Pipeline [#{push_pipeline['number']}]({push_pipeline_url}) "
                    f"ended with `{push_final['status']}`. Not tagging release."
                ),
            })
            return {"status": "build_failed", "commit": after_sha, "pipeline": push_pipeline["number"]}

        push_embed["color"] = EMBED_GREEN
        push_embed["fields"][-1] = {
            "name": "Build",
            "value": f"[#{push_pipeline['number']}]({push_pipeline_url}) — ✅ success",
            "inline": False,
        }
        discord.edit(push_msg_id, embed=push_embed)

        stage["name"] = "tag"
        tag_name = f"release-{after_version}"
        log(f"Tagging {after_sha[:10]} as {tag_name} and pushing")
        run(["git", "-C", repo_dir, "tag", "-a", tag_name, "-m", tag_name, after_sha])
        run(["git", "-C", repo_dir, "push", "origin", tag_name])
        log("Tag pushed")

        release_url = f"{forgejo_base_url.rstrip('/')}/{repo_owner}/{repo_name}/releases/tag/{tag_name}"
        tag_embed = {
            "title": f"🏷 Tagged `{tag_name}`",
            "url": release_url,
            "color": EMBED_BLUE,
            "fields": [
                {"name": "Tag", "value": f"[`{tag_name}`]({release_url})", "inline": True},
                {"name": "Commit", "value": f"[`{after_sha[:10]}`]({commit_url})", "inline": True},
                {"name": "Build", "value": "_waiting for tag pipeline…_", "inline": False},
            ],
        }
        tag_msg_id = discord.post_embed(tag_embed)
        log(f"Posted tag embed (Discord msg {tag_msg_id})")

        stage["name"] = "discover_tag_pipeline"
        tag_ref = f"refs/tags/{tag_name}"
        log(f"Looking for Woodpecker pipeline matching {tag_ref} (up to {pipeline_discover_timeout}s)")
        tag_pipeline = woodpecker.find_pipeline(
            lambda p: p.get("ref") == tag_ref or (
                p.get("event") == "tag" and p.get("commit") == after_sha
            ),
            timeout=pipeline_discover_timeout,
        )
        if tag_pipeline is None:
            log("No tag pipeline found within discover timeout")
            tag_embed["color"] = EMBED_YELLOW
            tag_embed["fields"][-1] = {
                "name": "Build",
                "value": "_no tag pipeline appeared — check manually_",
                "inline": False,
            }
            discord.edit(tag_msg_id, embed=tag_embed)
            return {"status": "tagged_no_pipeline", "tag": tag_name}

        tag_pipeline_url = woodpecker.pipeline_url(tag_pipeline["number"])
        log(f"Found tag pipeline #{tag_pipeline['number']} ({tag_pipeline_url})")
        tag_embed["fields"][-1] = {
            "name": "Build",
            "value": f"[#{tag_pipeline['number']}]({tag_pipeline_url}) — running…",
            "inline": False,
        }
        discord.edit(tag_msg_id, embed=tag_embed)

        stage["name"] = "wait_tag_build"
        log(f"Waiting for pipeline #{tag_pipeline['number']} (poll every {pipeline_poll_interval}s, timeout {build_timeout_seconds}s)")
        tag_final = woodpecker.wait_for_pipeline(
            tag_pipeline["number"],
            timeout=build_timeout_seconds,
            interval=pipeline_poll_interval,
            label=f"tag#{tag_pipeline['number']}",
        )
        log(f"Tag pipeline #{tag_pipeline['number']} ended: {tag_final['status']}")

        if tag_final["status"] != "success":
            tag_embed["color"] = EMBED_RED
            tag_embed["fields"][-1] = {
                "name": "Build",
                "value": f"[#{tag_pipeline['number']}]({tag_pipeline_url}) — **{tag_final['status']}**",
                "inline": False,
            }
            discord.edit(tag_msg_id, embed=tag_embed)
            discord.post_embed({
                "title": f"❌ Release build failed for `{tag_name}`",
                "url": tag_pipeline_url,
                "color": EMBED_RED,
                "description": (
                    f"Tag pipeline [#{tag_pipeline['number']}]({tag_pipeline_url}) "
                    f"ended with `{tag_final['status']}`."
                ),
            })
            return {"status": "tag_build_failed", "tag": tag_name}

        tag_embed["color"] = EMBED_GREEN
        tag_embed["fields"][-1] = {
            "name": "Build",
            "value": f"[#{tag_pipeline['number']}]({tag_pipeline_url}) — ✅ success",
            "inline": False,
        }
        discord.edit(tag_msg_id, embed=tag_embed)

        discord.post_embed({
            "title": f"🎉 NightsEdge {after_version} released",
            "url": release_url,
            "color": EMBED_GREEN,
            "description": f"[`{tag_name}`]({release_url}) is live.",
        })
        log(f"Released {after_version} -> {release_url}")
        return {
            "status": "released",
            "version": after_version,
            "tag": tag_name,
            "release_url": release_url,
        }

    except subprocess.CalledProcessError as e:
        detail = ((e.stderr or "") + "\n" + (e.stdout or "")).strip()[-1500:] or "(empty)"
        cmd = " ".join(e.cmd) if isinstance(e.cmd, list) else str(e.cmd)
        log(f"FAILED during {stage['name']}: `{cmd}` (exit {e.returncode})\n{detail}")
        DiscordWebhook(webhook_url).safe_post_embed({
            "title": f"❌ NightsEdge autoupdate failed during `{stage['name']}`",
            "color": EMBED_RED,
            "description": f"Command failed (exit {e.returncode}): `{cmd}`",
            "fields": [{"name": "Output", "value": f"```\n{detail}\n```", "inline": False}],
        })
        raise
    except Exception as e:
        log(f"FAILED during {stage['name']}: {type(e).__name__}: {e}")
        DiscordWebhook(webhook_url).safe_post_embed({
            "title": f"❌ NightsEdge autoupdate failed during `{stage['name']}`",
            "color": EMBED_RED,
            "description": f"{type(e).__name__}: {e}",
        })
        raise
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def read_version(repo_dir: str) -> str:
    with open(os.path.join(repo_dir, "FIREFOX_VERSION")) as f:
        for line in f:
            m = re.match(r"^\s*VERSION\s*=\s*[\"']?([^\"'\s#]+)", line)
            if m:
                return m.group(1)
    return "unknown"


class DiscordWebhook:
    def __init__(self, url: str):
        self.url = url

    def post(self, content: Optional[str] = None, embed: Optional[dict] = None) -> str:
        payload: dict = {}
        if content is not None:
            payload["content"] = content[:1900]
        if embed is not None:
            payload["embeds"] = [embed]
        r = requests.post(f"{self.url}?wait=true", json=payload, timeout=15)
        r.raise_for_status()
        return r.json()["id"]

    def post_embed(self, embed: dict) -> str:
        return self.post(embed=embed)

    def edit(self, message_id: str, content: Optional[str] = None, embed: Optional[dict] = None) -> None:
        payload: dict = {}
        if content is not None:
            payload["content"] = content[:1900]
        if embed is not None:
            payload["embeds"] = [embed]
        r = requests.patch(
            f"{self.url}/messages/{message_id}", json=payload, timeout=15
        )
        r.raise_for_status()

    def safe_post_embed(self, embed: dict) -> None:
        try:
            self.post_embed(embed)
        except Exception:
            pass


class WoodpeckerClient:
    def __init__(self, base_url: str, token: str, owner: str, name: str):
        self.base = base_url.rstrip("/")
        self.owner = owner
        self.name = name
        self.s = requests.Session()
        self.s.headers["Authorization"] = f"Bearer {token}"
        self._repo_id: Optional[int] = None

    def repo_id(self) -> int:
        if self._repo_id is None:
            r = self.s.get(
                f"{self.base}/api/repos/lookup/{self.owner}/{self.name}", timeout=15
            )
            r.raise_for_status()
            self._repo_id = r.json()["id"]
        return self._repo_id

    def list_pipelines(self, page: int = 1, per_page: int = 50) -> list:
        r = self.s.get(
            f"{self.base}/api/repos/{self.repo_id()}/pipelines",
            params={"page": page, "perPage": per_page},
            timeout=15,
        )
        r.raise_for_status()
        return r.json() or []

    def get_pipeline(self, number: int) -> dict:
        r = self.s.get(
            f"{self.base}/api/repos/{self.repo_id()}/pipelines/{number}", timeout=15
        )
        r.raise_for_status()
        return r.json()

    def find_pipeline(
        self, predicate: Callable[[dict], bool], timeout: int = 180
    ) -> Optional[dict]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            for p in self.list_pipelines():
                if predicate(p):
                    return p
            time.sleep(5)
        return None

    def wait_for_pipeline(
        self, number: int, timeout: int, interval: int, label: str = ""
    ) -> dict:
        deadline = time.time() + timeout
        last_status: Optional[str] = None
        tag = f"[{label}] " if label else ""
        while time.time() < deadline:
            p = self.get_pipeline(number)
            status = p.get("status")
            if status != last_status:
                log(f"{tag}status: {last_status or '(none)'} -> {status}")
                last_status = status
            if status in TERMINAL_STATUSES:
                return p
            time.sleep(interval)
        raise TimeoutError(f"pipeline #{number} did not finish within {timeout}s")

    def pipeline_url(self, number: int) -> str:
        return f"{self.base}/repos/{self.repo_id()}/pipeline/{number}"
