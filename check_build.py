#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
查询 RAX3000QY 云编译状态。
- 成功：从 Release 下载 .ubi 到 ../output/
- 失败：打印哪个 job / 哪个 step 挂了 + 日志尾部
用法:
    python check_build.py
"""
import json
import os
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

OWNER = "ngsxmb9609260"
REPO = "Actions-OpenWrt-RAX3000Q"
RUN_ID = 37961191310  # 兜底值；若 run_info.json 存在则以其为准

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUTDIR = os.path.join(ROOT, "output")
TOKEN_PATH = os.path.join(ROOT, ".gh_token")

# push_and_build.py 每次触发编译后会把最新的 run_id 写进 run_info.json
_run_info = os.path.join(HERE, "run_info.json")
if os.path.exists(_run_info):
    try:
        with open(_run_info, encoding="utf-8") as _f:
            RUN_ID = json.load(_f).get("run_id", RUN_ID)
    except Exception:
        pass

SSL_OK = ssl.create_default_context()
SSL_NO = ssl._create_unverified_context()
USE_NO = False
TOKEN = ""


def api(method, path, payload=None, raw=False):
    global USE_NO
    url = "https://api.github.com" + path
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "rax3000qy-check")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    ctx = SSL_NO if USE_NO else SSL_OK
    try:
        with urllib.request.urlopen(req, timeout=120, context=ctx) as r:
            body = r.read()
            return r.status, (body if raw else json.loads(body or b"{}"))
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body or b"{}")
        except Exception:
            return e.code, {"raw": body.decode("utf-8", "replace")}
    except Exception as e:
        if not USE_NO:
            USE_NO = True
            return api(method, path, payload, raw)
        raise


def dl(url, dest):
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/octet-stream")
    req.add_header("User-Agent", "rax3000qy-check")
    ctx = SSL_NO if USE_NO else SSL_OK
    while True:
        try:
            with urllib.request.urlopen(req, timeout=300, context=ctx) as r, open(dest, "wb") as f:
                total = 0
                while True:
                    chunk = r.read(262144)
                    if not chunk:
                        break
                    f.write(chunk)
                    total += len(chunk)
            return total
        except Exception:
            if not USE_NO:
                USE_NO = True
                continue
            raise


def job_log(job_id):
    """抓取 job 全量日志文本。

    urllib 打 /actions/jobs/<id>/logs 在 Windows 上常返回 401（重定向到
    对象存储后鉴权丢失），因此失败时回退到 curl --ssl-no-revoke。
    """
    st, log = api("GET", "/repos/%s/%s/actions/jobs/%s/logs" % (OWNER, REPO, job_id), raw=True)
    if st == 200 and isinstance(log, bytes):
        return log.decode("utf-8", "replace")

    url = "https://api.github.com/repos/%s/%s/actions/jobs/%s/logs" % (OWNER, REPO, job_id)
    fd, tmp = tempfile.mkstemp(suffix=".log")
    os.close(fd)
    try:
        subprocess.run(
            ["curl", "-sSL", "--ssl-no-revoke", "-o", tmp,
             "-H", "Authorization: Bearer " + TOKEN,
             "-H", "X-GitHub-Api-Version: 2022-11-28",
             "-H", "User-Agent: rax3000qy-check",
             "-H", "Accept: application/vnd.github+json",
             url],
            capture_output=True, timeout=300)
        if os.path.getsize(tmp) > 0:
            with open(tmp, "rb") as f:
                return f.read().decode("utf-8", "replace")
    except Exception as e:
        print("  [warn] curl 回退抓日志失败:", e)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass
    return None


ERROR_KEYS = (
    "ERROR: package", "failed to build", "Error 1", "Error 2",
    "undefined reference", "No space left", "not found", "Permission denied",
)


def main():
    global TOKEN
    with open(TOKEN_PATH, encoding="utf-8") as f:
        TOKEN = f.read().strip()

    st, r = api("GET", "/repos/%s/%s/actions/runs/%s" % (OWNER, REPO, RUN_ID))
    if st != 200:
        print("!! 无法读取运行信息 HTTP", st, r)
        sys.exit(1)

    status = r.get("status")
    concl = r.get("conclusion")
    print("=" * 62)
    print("RAX3000QY 云编译状态")
    print("=" * 62)
    print("  run_id     :", RUN_ID)
    print("  状态       :", status, "/", concl)
    print("  提交       :", r.get("head_sha", "")[:8])
    print("  开始       :", r.get("created_at"))
    print("  更新       :", r.get("updated_at"), "（API 的 updated_at，非真实结束时间）")
    print("  网页       :", r.get("html_url"))

    if status != "completed":
        print("")
        print(">>> 编译仍在进行中，请稍后再查。")
        return

    # 打印各 job / step
    print("")
    print("--- 各作业 ---")
    st, jobs = api("GET", "/repos/%s/%s/actions/runs/%s/jobs" % (OWNER, REPO, RUN_ID))
    failed_steps = []
    for j in jobs.get("jobs", []):
        print("  [%s] %s" % (j.get("conclusion"), j.get("name")))
        for s in j.get("steps", []):
            mark = " " if s.get("conclusion") == "success" else "*"
            print("     %s %-38s %s" % (mark, s.get("name"), s.get("conclusion")))
            if s.get("conclusion") not in ("success", "skipped", None):
                failed_steps.append((j.get("name"), s.get("name")))

    if concl == "success":
        print("")
        print(">>> 编译成功，开始下载产物")
        os.makedirs(OUTDIR, exist_ok=True)
        # 1) 优先从 Release 找
        st, rels = api("GET", "/repos/%s/%s/releases?per_page=5" % (OWNER, REPO))
        got = 0
        if st == 200:
            for rel in rels:
                for a in rel.get("assets", []):
                    n = a["name"]
                    if n.endswith(".ubi") or ("rax3000q" in n.lower() and n.endswith((".bin", ".itb", ".ubi"))):
                        dest = os.path.join(OUTDIR, n)
                        size = dl(a["browser_download_url"], dest)
                        print("  下载 %-52s %6.2f MB" % (n, size / 1048576))
                        got += 1
        if not got:
            print("  !! Release 中未找到产物，请到 actions 页面 Artifacts 手动下载")
            print("     ", r.get("html_url"))
        else:
            print("")
            print(">>> 产物已保存到:", OUTDIR)
    else:
        print("")
        print(">>> 编译失败！失败步骤:")
        for jn, sn in failed_steps:
            print("   - %s / %s" % (jn, sn))
        # 抓失败 job 的日志尾部
        for j in jobs.get("jobs", []):
            if j.get("conclusion") == "failure":
                text = job_log(j["id"])
                if not text:
                    print("")
                    print("  !! job [%s] 日志抓取失败（可直接看网页）" % j.get("name"))
                    continue
                lines = text.splitlines()
                print("")
                print("--- job [%s] 日志尾部（共 %d 行，取末 80 行）---" % (j.get("name"), len(lines)))
                print("\n".join(lines[-80:]))

                hits = [l for l in lines if any(k in l for k in ERROR_KEYS)]
                if hits:
                    print("")
                    print("--- 关键报错行 ---")
                    for l in hits[-25:]:
                        print(l)


if __name__ == "__main__":
    main()
