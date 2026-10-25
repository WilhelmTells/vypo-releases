# Third-party notices

vypo is made by Wilhelm Tells. It is built on the work of others, listed here with the licenses that
require us to name them. This file is the single source: the app shows it in **About vypo** (it is
bundled as a resource, not copied), and `NoticesTests` fails if a Swift package in `project.yml` has no
entry here.

Format (the app and the test read it): every entry under `## Built in` and `## Downloaded models` is a
`###` heading followed by `- Key: value` lines (`Package`, `Version`, `Author`, `License`, `Source`,
`Use`), then free text. `License` is `[Name](url)`. Full license texts are under `## License texts`.

## Built in

### FluidAudio
- Package: FluidAudio
- Version: 0.17.7
- Author: FluidInference
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/FluidInference/FluidAudio
- Use: Swift package, speech recognition runtime (Core ML).

Copyright FluidInference Team (named in the package's `CITATION.cff`; its `LICENSE` file carries no
copyright line). Its source also contains the parts listed below, which are linked into vypo.

### KeyboardShortcuts
- Package: KeyboardShortcuts
- Version: 3.1.0
- Author: Sindre Sorhus
- License: [MIT](https://opensource.org/license/mit)
- Source: https://github.com/sindresorhus/KeyboardShortcuts
- Use: Swift package, the global shortcuts.

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

### Apache Commons Codec (Double Metaphone)
- Author: The Apache Software Foundation
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/apache/commons-codec
- Use: translated into Swift (`vypo/Text/DoubleMetaphone.swift`), used to match glossary terms by sound.

vypo's `DoubleMetaphone` is a Swift translation of `org.apache.commons.codec.language.DoubleMetaphone`
(same conditions, same order, same literals). Changes: translated from Java to Swift; only the primary
code is kept, with a maximum length of 6; the alternate code, `setMaxCodeLen` and the encoder interfaces
are dropped. The algorithm is by Lawrence Philips.

Apache Commons Codec, Copyright 2002-2026 The Apache Software Foundation. This product includes software
developed at The Apache Software Foundation (https://www.apache.org/).

### fastcluster
- Author: Daniel Müllner; Google Inc.
- License: [BSD-2-Clause](https://opensource.org/license/bsd-2-clause)
- Source: https://github.com/fastcluster/fastcluster
- Use: part of FluidAudio (centroid linkage clustering), linked into vypo.

Copyright: until version 1.1.23 © 2011 Daniel Müllner <https://danifold.net>; all changes from version
1.1.24 on © Google Inc. <https://www.google.com>.

### VBx
- Author: BUT Speech@FIT
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/BUTSpeechFIT/VBx
- Use: part of FluidAudio (speaker clustering, a Swift port), linked into vypo.

Copyright 2021-2024 BUT Speech@FIT (original VBx project).

### NeMo Text Processing and text-processing-rs
- Author: NVIDIA; FluidInference
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/NVIDIA/NeMo-text-processing, https://github.com/FluidInference/text-processing-rs
- Use: part of FluidAudio (text normalization, a prebuilt library), linked into vypo.

The compiled grammars derive from NVIDIA NeMo Text Processing, Copyright (c) NVIDIA CORPORATION &
AFFILIATES. The library is `text-processing-rs` v0.3.1 by FluidInference.

### rustfst, flate2 and other Rust crates
- Author: Alexandre Caulier and the rustfst contributors; Alex Crichton and the flate2 contributors
- License: [MIT](https://opensource.org/license/mit) or [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/Garvys/rustfst, https://github.com/rust-lang/flate2-rs
- Use: statically linked into the text-processing library above.

Copyright (c) Alexandre Caulier and the rustfst contributors; Copyright (c) Alex Crichton and the flate2
contributors. The library also links further crates under MIT and/or Apache-2.0 (for example nom,
miniz_oxide, bitflags, anyhow), named in the notice of text-processing-rs.

### Misaki
- Author: hexgrad
- License: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)
- Source: https://github.com/hexgrad/misaki
- Use: part of FluidAudio (Japanese text frontend, a Swift port), linked into vypo.

### cutlet
- Author: Paul O'Leary McCann
- License: [MIT](https://opensource.org/license/mit)
- Source: https://github.com/polm/cutlet
- Use: part of FluidAudio (Japanese text frontend, via Misaki), linked into vypo.

Copyright (c) 2020 Paul O'Leary McCann

### Convert-Numbers-to-Japanese
- Author: David Wilson
- License: [MIT](https://opensource.org/license/mit)
- Source: https://github.com/Greatdane/Convert-Numbers-to-Japanese
- Use: part of FluidAudio (Japanese number reading), linked into vypo.

Copyright (c) 2018 David Wilson, https://github.com/Greatdane

### Sparkle
- Package: Sparkle
- Version: 2.10.0
- Author: Andy Matuschak and the Sparkle Project
- License: [MIT](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)
- Source: https://github.com/sparkle-project/Sparkle
- Use: Swift package, the updater (`Sparkle.framework` in the app).

Copyright (c) 2006-2013 Andy Matuschak; (c) 2009-2013 Elgato Systems GmbH; (c) 2011-2014 Kornel Lesiński;
(c) 2015-2017 Mayur Pawashe; (c) 2014 C.W. Betts; (c) 2014 Petroules Corporation; (c) 2014 Big Nerd Ranch.
Sparkle brings the four components below with it; their texts are in the Sparkle license under License texts.

### bsdiff and bspatch
- Author: Colin Percival
- License: [BSD](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)
- Source: http://www.daemonology.net/bsdiff/
- Use: part of Sparkle (delta updates), in `Sparkle.framework`.

Copyright 2003-2005 Colin Percival.

### sais-lite
- Author: Yuta Mori
- License: [MIT](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)
- Source: https://sites.google.com/site/yuta256/sais
- Use: part of Sparkle (with bsdiff), in `Sparkle.framework`.

Copyright (c) 2008-2010 Yuta Mori.

### ed25519 (portable C implementation)
- Author: Orson Peters
- License: [zlib](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)
- Source: https://github.com/orlp/ed25519
- Use: part of Sparkle (checks the update's EdDSA signature), in `Sparkle.framework`.

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>.

### SUSignatureVerifier
- Author: Mark Hamlin
- License: [BSD](https://github.com/sparkle-project/Sparkle/blob/2.10.0/LICENSE)
- Source: https://github.com/sparkle-project/Sparkle
- Use: part of Sparkle (signature checking code), in `Sparkle.framework`.

Copyright (c) 2011 Mark Hamlin.

## Downloaded models

The speech models are not part of the app. vypo downloads them from Hugging Face when you choose to, and
runs them on your Mac. Each model is licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); the chain below gives each link its title,
author, source and license, and says what was changed. The authors do not endorse vypo.

### Parakeet Ultra
- Author: moondream
- License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- Source: https://huggingface.co/FluidInference/parakeet-ultra-coreml
- Use: the speech model for every language, downloaded in onboarding or Settings.

The chain:
1. "parakeet-tdt-0.6b-v3" by NVIDIA, https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3, CC BY 4.0.
2. "Moondream Parakeet Ultra" by moondream, https://huggingface.co/moondream/parakeet-ultra, CC BY 4.0.
   Changed: post-trained from (1).
3. "parakeet-ultra-coreml" by FluidInference, https://huggingface.co/FluidInference/parakeet-ultra-coreml,
   CC BY 4.0. Changed: converted from (2) to Core ML, encoder quantized to int8.

vypo uses (3) without further changes.

### Parakeet CTC 110M
- Author: NVIDIA
- License: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- Source: https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml
- Use: the glossary helper, off by default; downloaded only when it is turned on.

The chain:
1. "parakeet-tdt_ctc-110m" by NVIDIA, https://huggingface.co/nvidia/parakeet-tdt_ctc-110m, CC BY 4.0.
2. "parakeet-ctc-110m-coreml" by FluidInference, https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml.
   Changed: converted from (1) to Core ML. Its metadata says CC BY 4.0 (its text says Apache 2.0); vypo
   follows the stricter of the two, the original's CC BY 4.0.

## License texts

### Apache License 2.0

Applies to FluidAudio, Apache Commons Codec, VBx, NeMo Text Processing, text-processing-rs, Misaki and
(at your choice) rustfst and flate2.

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```

### MIT License

Applies to KeyboardShortcuts, cutlet, Convert-Numbers-to-Japanese and (at your choice) rustfst and flate2.

```text
Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)
Copyright (c) 2020 Paul O'Leary McCann
Copyright (c) 2018 David Wilson, https://github.com/Greatdane
Copyright (c) Alexandre Caulier and the rustfst contributors
Copyright (c) Alex Crichton and the flate2 contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### BSD 2-Clause License

Applies to fastcluster.

```text
Copyright:
  * Until package version 1.1.23: © 2011 Daniel Müllner <https://danifold.net>
  * All changes from version 1.1.24 on: © Google Inc. <https://www.google.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Sparkle license

Applies to Sparkle, bsdiff, sais-lite, ed25519 and SUSignatureVerifier, as published in Sparkle 2.10.0.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

### Creative Commons Attribution 4.0 International

Applies to the speech models. The full legal text is at
https://creativecommons.org/licenses/by/4.0/legalcode.en
