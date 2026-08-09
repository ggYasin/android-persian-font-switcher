# Third-party font notices

Module code and documentation are MIT licensed. Font software retains its upstream license. Exact Regular/Bold SHA-256 values plus a source-archive SHA-256 or source commit are pinned in [`webroot/font-manifest.json`](webroot/font-manifest.json); each license is shipped at the manifest's `licensePath`.

| Font | Version | Author/project | Official source | License |
| --- | --- | --- | --- | --- |
| Vazirmatn | 33.003 | Saber Rastikerdar / project authors | [release](https://github.com/rastikerdar/vazirmatn/releases/tag/v33.003) | OFL-1.1 |
| Estedad | 8.5 | Amin Abedi / project authors | [release](https://github.com/aminabedi68/Estedad/releases/tag/8.5) | OFL-1.1 |
| Sahel | 3.4.0 | Saber Rastikerdar | [release](https://github.com/rastikerdar/sahel-font/releases/tag/v3.4.0) | OFL-1.1; upstream Apache notice retained |
| Shabnam | 5.0.1 | Saber Rastikerdar | [release](https://github.com/rastikerdar/shabnam-font/releases/tag/v5.0.1) | OFL-1.1; upstream notices retained |
| Samim | 4.0.5 | Saber Rastikerdar | [release](https://github.com/rastikerdar/samim-font/releases/tag/v4.0.5) | OFL-1.1; upstream notices retained |
| Tanha | 0.10 | Saber Rastikerdar | [release](https://github.com/rastikerdar/tanha-font/releases/tag/v0.10) | Public-domain changes plus Apache and Bitstream Vera terms in combined LICENSE |
| Gandom | 0.8 | Saber Rastikerdar | [release](https://github.com/rastikerdar/gandom-font/releases/tag/v0.8) | OFL-1.1; upstream notices retained |
| Parastoo | 2.0.1 | Saber Rastikerdar | [release](https://github.com/rastikerdar/parastoo-font/releases/tag/v2.0.1) | OFL-1.1 |
| Mikhak | 3.4 | Amin Abedi / project authors | [release](https://github.com/aminabedi68/Mikhak/releases/tag/3.4) | OFL-1.1 |
| Cairo | 3.116 | Mohamed Gaber / project authors | [tag](https://github.com/Gue3bara/Cairo/releases/tag/v3.116) | OFL-1.1 |
| Noto Sans Arabic | 2.013 | Noto Project Authors | [release](https://github.com/notofonts/arabic/releases/tag/NotoSansArabic-v2.013) | OFL-1.1 |
| Noto Kufi Arabic | 2.110 | Noto Project Authors | [release](https://github.com/notofonts/arabic/releases/tag/NotoKufiArabic-v2.110) | OFL-1.1 |
| IBM Plex Sans Arabic | package 1.1.0 / font 1.005 | IBM / Bold Monday | [release](https://github.com/IBM/plex/releases/tag/%40ibm/plex-sans-arabic%401.1.0) | OFL-1.1; Reserved Font Name Plex |

Vazirmatn, Sahel, Shabnam, Samim, Gandom, Parastoo, and Tanha use official upstream non-Latin variants. Tanha and Gandom publish no Bold file; the unchanged single upstream weight is duplicated for the Android Bold target and disclosed in the UI/manifest.

## Why IRANSans is not included

The supplied [`akiarostami/iransans`](https://github.com/akiarostami/iransans) mirror does not grant font redistribution rights. Its README says users must obtain rights from FontIran, it includes no font license, and the binaries identify FontIran/Moslem Ebrahimi with “All rights reserved.” The package's MIT metadata covers source/CSS packaging, not those font binaries.

No IRANSans binary, preview, or manifest entry is distributed. Users who possess applicable rights can import their own files locally through the custom-font feature; those files remain on their device and under their responsibility.
