# Third-party notices

CloudTune's own Apple TV 3 client, Mac bridge glue code, packaging scripts, branding, and documentation are published as part of this repository.

## External API dependency

CloudTune Bridge expects a locally running **NeteaseCloudMusicApi-compatible** HTTP service. That upstream implementation is **not bundled or redistributed in this repository**.

Development was tested against:

- Project: NeteaseCloudMusicApi
- Version: 4.32.0
- Author: Binaryify
- Copyright: Copyright (c) 2013-2022 Binaryify
- License: MIT

The upstream project later stopped active maintenance. Users must obtain and operate any compatible upstream service themselves and are responsible for complying with the music provider's terms, applicable laws, and the upstream software's license.

For attribution, the MIT text distributed with version 4.32.0 is reproduced below:

> The MIT License (MIT)
>
> Copyright (c) 2013-2022 Binaryify
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.

## Provider content and accounts

NetEase Cloud Music names, accounts, catalog metadata, lyrics, artwork, and audio streams are third-party content/services and are not licensed by this repository. CloudTune does not include music files.

The bridge uses the user's own authenticated provider session. If the upstream provider does not authorize a playback URL, CloudTune returns the item as unavailable rather than bypassing that restriction.
