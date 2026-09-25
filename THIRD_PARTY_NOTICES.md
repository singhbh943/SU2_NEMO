# Third-Party Notices

This repository contains SU2-derived source and uses Mutation++ as a pinned Git submodule. It also references other upstream dependencies through SU2's existing submodule/build system.

## SU2

The repository retains the upstream SU2 license and attribution materials, including `COPYING`, `LICENSE.md`, `AUTHORS.md`, and the original source-file notices.

The retained `COPYING` and `LICENSE.md` files contain GNU Lesser General Public License version 2.1 text. Those files, together with the notices in individual source files, govern the SU2-derived portions of this repository.

Upstream project:

https://github.com/su2code/SU2

## Mutation++

Mutation++ is used through the pinned submodule:

```text
subprojects/Mutationpp
```

The v0.1.0 release line pins the hardened Mutation++ fork used by the validated build. The packaged runtime copies the submodule's license text into its documentation.

A license-metadata inconsistency is present in the pinned Mutation++ revision: its `COPYING` file contains GNU General Public License version 3 text, while its README badge identifies the project as LGPL v3. This notice does not attempt to reinterpret or replace those upstream materials. Users and redistributors should inspect the exact pinned submodule revision and its license/notices directly.

Pinned fork:

https://github.com/singhbh943/Mutationpp

Upstream Mutation++ project:

https://github.com/mutationpp/Mutationpp

## Other SU2 dependencies

Other dependencies referenced through SU2's existing build system and submodules remain subject to their own licenses and notices. This repository does not replace those terms.

## Release packaging

The source release preserves the corresponding source, build scripts, submodule references, implementation records, and license files used to build the distributed runtime. Portable/runtime artifacts should be distributed together with their generated documentation and provenance files.

This notice is informational and does not replace the actual license texts shipped with each component.
