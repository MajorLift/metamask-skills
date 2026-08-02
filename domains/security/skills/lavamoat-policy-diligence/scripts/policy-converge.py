#!/usr/bin/env python3
"""Ask whether a policy's new capabilities are new to the CODEBASE, or only to this policy.

`policy-audit.py` enumerates what a policy gained and refuses to judge it. That is the right
default for a dependency bump. It is the wrong shape for a build-configuration change — a
service-worker wrapping, an entry-point move — where the honest question is not "is each of
these 1100 grants justified" but "is any of them a decision this change actually made".

A grant that the sibling policy has been granting all along was not chosen here. It arrives
because a package that was already running uncontained is now contained and therefore
enumerated. Counting those as new capabilities reads a containment improvement as a
capability expansion, which is backwards.

So this compares three policies rather than two:

    --base       the policy under review, before the change
    --head       the same policy, after
    --reference  the SIBLING policy the head should converge on (typically mv2/main)

and reports the only number that distinguishes the two readings: how many of head's new
grants are absent from the reference. Zero means convergence. Non-zero is the finding, and
every one of them is listed — there is no summarising a novel capability away.

Overrides are handled separately and NOT counted as convergence. An entry added by hand to
`policy-override.json` is a decision somebody made in this diff, whatever the generated
policy says, so each is printed with the file and line where it can be read.

    policy-converge.py --base <p> --head <p> --reference <p>
                       [--override-base <p> --override-head <p>]
                       [--override-path <repo-relative path for citation>]

Falsifier: a grant new to head, absent from the reference, that the summary does not name.
Exit 0 always — the reading is the caller's, as everywhere else in this suite.
"""
import json
import sys

KINDS = ("globals", "builtins", "packages")


def resources(path):
    with open(path) as f:
        return json.load(f).get("resources", {})


def grants(res):
    """Every (pkg, kind, capability) the policy actually grants."""
    out = set()
    for pkg, cfg in res.items():
        for kind in KINDS:
            for cap, val in (cfg.get(kind) or {}).items():
                if val:
                    out.add((pkg, kind, cap))
    return out


def override_entries(path):
    """Top-level override resources, as {pkg: config}."""
    if not path:
        return {}
    with open(path) as f:
        return json.load(f).get("resources", {})


def line_of(path, key):
    """1-based line where `"<key>"` appears, so a finding can be cited rather than described.

    A row naming a package with no way to reach it is the same defect as an uncaptured
    console block, and the override files are small enough that a literal scan is exact.
    """
    if not path:
        return None
    needle = f'"{key}"'
    try:
        with open(path) as f:
            for n, line in enumerate(f, 1):
                if needle in line:
                    return n
    except OSError:
        return None
    return None


def arg(args, name, required=True):
    if name in args:
        i = args.index(name)
        if i + 1 < len(args):
            return args[i + 1]
    if required:
        sys.exit(f"policy-converge.py: {name} is required")
    return None


def main():
    a = sys.argv[1:]
    base_p = arg(a, "--base")
    head_p = arg(a, "--head")
    ref_p = arg(a, "--reference")
    ob_p = arg(a, "--override-base", False)
    oh_p = arg(a, "--override-head", False)
    cite = arg(a, "--override-path", False) or oh_p

    base, head, ref = resources(base_p), resources(head_p), resources(ref_p)
    gb, gh, gr = grants(base), grants(head), grants(ref)

    added = gh - gb
    covered = added & gr
    novel = sorted(added - gr)

    print("CONTAINMENT CONVERGENCE")
    print("=" * 74)
    print(f"contained packages   base {len(base):>5}  ->  head {len(head):>5}")
    print(f"reference policy     {ref_p}  ({len(ref)} packages)")
    print()
    print(f"grants new to head between base and head:  {len(added)}")
    print(f"  of those, already granted in reference:  {len(covered)}")
    print(f"  new to head and ABSENT from reference:   {len(novel)}")
    print()

    if not novel:
        print("None. Every capability the head policy gains is one the reference already")
        print("grants, so the surface converges on the existing baseline rather than")
        print("extending it. This says nothing about whether the reference is correctly")
        print("scoped — an over-broad grant inherited from it is still over-broad.")
    else:
        print("Novel to the codebase. Each of these is a capability the reference does NOT")
        print("grant, so it cannot be explained by containment alone:")
        for pkg, kind, cap in novel:
            print(f"  [?] {pkg[:44]:46s} {kind[:3]}:{cap}")

    added_over = {}
    if oh_p:
        ob, oh = override_entries(ob_p), override_entries(oh_p)
        added_over = {k: v for k, v in oh.items() if k not in ob}
        print()
        print("-" * 74)
        print(f"hand-written override entries added by this change: {len(added_over)}")
        print("Convergence does not cover these. An override is written by a person, so")
        print("each is a decision this diff made, and each is cited where it can be read.")
        print()
        for k, v in sorted(added_over.items()):
            ln = line_of(oh_p, k)
            where = f"{cite}:{ln}" if ln else cite
            print(f"    {k}")
            print(f"      {json.dumps(v.get('globals', v))}")
            print(f"      cite: {where}")


if __name__ == "__main__":
    main()
