# Header and search-results pictures

The App Store's product page header (21:9, an 8-second silent loop) and the picture shown in search results (3:2), one per store language, in the look of Roman's 1.0 screenshots: his three phones on the blush-to-red light, the brand in Georgia and a one-line tagline (#338).

```
python3 store/assets/make_assets.py            # every language in texts.py
python3 store/assets/make_assets.py de-DE uk   # just these
```

Out, per language, in `store/assets/out/<locale>/` (not in git; under 3 MB each):

| File | What | Apple's size |
| --- | --- | --- |
| `header.mp4` | Product page header, 8 s loop, 30 fps, H.264, no sound | 3840×1646 |
| `header-poster.jpg` | Its first frame | 3840×1646 |
| `iphone-header.jpg` | The part an iPhone shows (x 555–3285), to check by eye | – |
| `search.png` | Search results picture | 3840×2560 |

- The phones are cut from `store/shots-1.0/` (the three live screenshots, downloaded from App Store Connect on 16 Nov) by hand-measured corners (`PHONES` in the script). New screenshots need new corners.
- Words: `texts.py`. They sit inside Apple's safe areas (header 1646×661 at 1097,493; search 2168×1030 at 836,765) and below the store's floating buttons.
- Needs Python 3 with Pillow, ffmpeg, and the macOS Georgia fonts.
- Uploading, review and placement per language: `~/Documents/independence-army-alarm/products/army-alarm/store/ASSET-PLAYBOOK.md`. Nothing is uploaded without Yurii's yes.
