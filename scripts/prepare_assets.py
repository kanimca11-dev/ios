"""Render existing brand assets for Apple's asset catalog; never crop the supplied wizard art."""
import io
import json
from pathlib import Path
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.parse import urlparse
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]

class HTTPSRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if urlparse(newurl).scheme != 'https':
            raise ValueError('Only HTTPS image redirects are allowed')
        return super().redirect_request(req, fp, code, msg, headers, newurl)

def download(url):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.username or parsed.password:
        raise ValueError('Image URL must be HTTPS without credentials')
    with build_opener(HTTPSRedirect()).open(Request(url), timeout=15) as response:
        data = response.read(8 * 1024 * 1024 + 1)
    if len(data) > 8 * 1024 * 1024:
        raise ValueError('Brand image exceeds 8 MB')
    image = Image.open(io.BytesIO(data))
    if image.width * image.height > 16000000:
        raise ValueError('Brand image exceeds 16 megapixels')
    image.load()
    image = ImageOps.exif_transpose(image)
    return image.convert('RGBA')

def image_set(name, filename):
    folder = ROOT / 'AppifyWebiOS/Assets.xcassets' / (name + '.imageset')
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'Contents.json').write_text(json.dumps({'images': [{'idiom': 'universal', 'filename': filename}], 'info': {'author': 'xcode', 'version': 1}}))
    return folder

def main():
    config = json.loads((ROOT / '.build-config.json').read_text())
    color = config.get('background', '#FFFFFF')
    # A wizard background is authoritative for launch continuity; inspect its corner color.
    if config.get('splash_url'):
        splash = download(config['splash_url'])
        color = '#%02x%02x%02x' % splash.convert('RGB').getpixel((0, 0))
        splash.thumbnail((1080, 1920), Image.Resampling.LANCZOS)
        splash.save(image_set('LaunchSplash', 'launch_splash.png') / 'launch_splash.png')
    if len(color.lstrip('#')) == 3:
        color = '#' + ''.join(c * 2 for c in color.lstrip('#'))
    if len(color.lstrip('#')) != 6:
        raise ValueError('Launch background must be a hex RGB color')
    rgb = [int(color.lstrip('#')[i:i+2], 16) / 255 for i in (0, 2, 4)]
    colors = {'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb', 'components': dict(zip(['red','green','blue','alpha'], [f'{x:.5f}' for x in rgb] + ['1.00000']))}}], 'info': {'author': 'xcode', 'version': 1}}
    (ROOT / 'AppifyWebiOS/Assets.xcassets/LaunchBackgroundColor.colorset/Contents.json').write_text(json.dumps(colors))
    if config.get('logo_url'):
        logo = download(config['logo_url'])
        logo.save(image_set('LaunchLogo', 'logo.png') / 'logo.png')
        folder = ROOT / 'AppifyWebiOS/Assets.xcassets/AppIcon.appiconset'
        sizes = [(40,'40'),(58,'58'),(60,'60'),(80,'80'),(87,'87'),(120,'120'),(180,'180'),(1024,'1024')]
        for size, suffix in sizes:
            canvas = Image.new('RGB', (size, size), 'white')
            thumb = ImageOps.contain(logo, (size, size), Image.Resampling.LANCZOS)
            canvas.paste(thumb, ((size-thumb.width)//2, (size-thumb.height)//2), thumb)
            canvas.save(folder / ('icon-' + suffix + '.png'))

if __name__ == '__main__':
    main()
