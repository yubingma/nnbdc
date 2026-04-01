import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageOps, ImageFont

INPUT_DIR = os.path.join(os.environ['PPDC_SRC_DIR'], 'devops/应用上架资源/ios')
OUTPUT_DIR = os.path.join(os.environ['PPDC_SRC_DIR'], 'devops/应用上架资源/huawei')
TARGET_SIZE = (450, 800)
FONT_PATH = os.path.join(os.environ['PPDC_SRC_DIR'], 'app/assets/fonts/NotoSansSC-Regular.ttf')

# Highlights mapping for each screenshot
HIGHLIGHTS = {
    '截屏-学习计划.png': '科学计划，掌握进度',
    '截屏-单词列表.png': '多维记忆，随心所欲',
    '截屏-词表.png': '灵活巩固，查漏补缺',
    '截屏-说中文.png': '一词多义，尽在掌握',
    '截屏-说英文.png': '脱口而出，自信表达',
    '截屏-我.png': '学习足迹，见证点滴成长',
    '截屏-词表说中文.png': '智能解析，深度强化词义记忆',
    '截屏-词表说英文.png': '快速刷词，分秒必争',
}

# Design Constants
PADDING_TOP = 140 # More room for text
PADDING_BOTTOM = 60
PADDING_SIDE = 50 # Slightly smaller phone

# Phone Frame Constants
FRAME_BEZEL_THICKNESS = 12
FRAME_COLOR = (20, 20, 20) # Near black
FRAME_CORNER_RADIUS = 40 # External radius
SCREEN_CORNER_RADIUS = 30 # Internal radius (screen)
BUTTON_COLOR = (40, 40, 40)

SHADOW_BLUR_RADIUS = 20
SHADOW_OFFSET = (0, 15)
SHADOW_OPACITY = 100  # 0-255

# Brand Colors (Blue Gradient as requested)
# Start: #00c6ff (Light Blue)
# End: #0072ff (Deep Blue)
COLOR_START = (0, 198, 255)
COLOR_END = (0, 114, 255)

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

def create_gradient(width, height, c1, c2):
    """Creates a linear gradient image (diagonal-ish) by resizing a small gradient."""
    base = Image.new('RGB', (100, 100), c1)
    top = Image.new('RGB', (100, 100), c2)
    mask = Image.new('L', (100, 100))
    mask_data = []
    for y in range(100):
        for x in range(100):
            # Diagonal gradient approx
            p = (x + y) / 200.0
            mask_data.append(int(255 * p))
    mask.putdata(mask_data)
    
    # Composite the small gradient
    gradient_small = Image.composite(top, base, mask)
    # Resize to target
    return gradient_small.resize((width, height), resample=Image.Resampling.BICUBIC)

def add_patterns(img):
    """Adds subtle decorative shapes to the background."""
    draw = ImageDraw.Draw(img, 'RGBA')
    w, h = img.size
    
    # Add a few large, soft white circles with higher opacity for visibility
    shapes = [
        (( -w*0.2, -h*0.1), w*0.8, (255, 255, 255, 50)),
        (( w*0.6, h*0.7), w*0.9, (255, 255, 255, 30)),
        (( w*0.1, h*0.4), w*0.3, (255, 255, 255, 40)),
        (( w*0.8, -h*0.2), w*0.4, (255, 255, 255, 35)),
    ]
    
    for (x, y), size, color in shapes:
        draw.ellipse([x, y, x+size, y+size], fill=color)
    
    return img

def create_phone_frame(screenshot):
    """Wraps the screenshot in a vector-style phone frame."""
    w, h = screenshot.size
    
    # Dimensions of the full device
    frame_w = w + (FRAME_BEZEL_THICKNESS * 2)
    frame_h = h + (FRAME_BEZEL_THICKNESS * 2)
    
    # 1. Create container
    # Use RGBA
    device = Image.new('RGBA', (frame_w, frame_h), (0,0,0,0))
    draw = ImageDraw.Draw(device)
    
    # 2. Draw Main Body (The "Chassis")
    # We draw a rounded rectangle
    draw.rounded_rectangle(
        [(0, 0), (frame_w, frame_h)], 
        radius=FRAME_CORNER_RADIUS, 
        fill=FRAME_COLOR
    )
    
    # 3. Apply Rounded Mask to Screenshot
    # We Reuse the add_rounded_corners logic but with specific screen radius
    screen_rounded = add_rounded_corners(screenshot, SCREEN_CORNER_RADIUS)
    
    # 4. Paste Screen onto Body
    # Centered
    device.paste(screen_rounded, (FRAME_BEZEL_THICKNESS, FRAME_BEZEL_THICKNESS), screen_rounded)
    
    # 5. Add "Punch Hole" camera (Generic Android/Huawei style)
    # Instead of a large Dynamic Island, use a small circle for a more brand-neutral look
    camera_radius = 6
    camera_x = frame_w / 2
    camera_y = FRAME_BEZEL_THICKNESS + 15
    
    draw.ellipse(
        [(camera_x - camera_radius, camera_y - camera_radius), 
         (camera_x + camera_radius, camera_y + camera_radius)],
        fill=(0, 0, 0, 255)
    )
    
    return device


def add_rounded_corners(img, radius):
    """Adds rounded corners to an image."""
    mask = Image.new('L', img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
    
    # Apply mask
    output = img.copy()
    output.putalpha(mask)
    return output

def create_drop_shadow(size, radius, offset, opacity):
    """Creates a shadow image."""
    shadow_width = size[0] + radius * 4
    shadow_height = size[1] + radius * 4
    shadow = Image.new('RGBA', (shadow_width, shadow_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    
    # Draw the shadow rectangle (slightly smaller to account for blur spreading)
    # We center it in the larger canvas
    rect_x0 = radius * 2
    rect_y0 = radius * 2
    rect_x1 = rect_x0 + size[0]
    rect_y1 = rect_y0 + size[1]
    
    draw.rounded_rectangle(
        [(rect_x0, rect_y0), (rect_x1, rect_y1)], 
        radius=FRAME_CORNER_RADIUS, 
        fill=(0, 0, 0, opacity)
    )
    
    # Blur
    return shadow.filter(ImageFilter.GaussianBlur(radius))

def draw_headline(bg, filename):
    """Draws a premium title at the top of the screenshot."""
    text = HIGHLIGHTS.get(filename, "精品单词，高效学习")
    draw = ImageDraw.Draw(bg, 'RGBA')
    
    # Text Shadow (subtle)
    try:
        font = ImageFont.truetype(FONT_PATH, 34)
    except Exception as e:
        print(f"Font loading failed: {e}")
        font = ImageFont.load_default()
        
    text_x = TARGET_SIZE[0] // 2
    text_y = 75 # Standard top height
    
    # Draw simple text with subtle drop shadow
    draw.text((text_x + 2, text_y + 2), text, font=font, anchor='mm', fill=(0, 0, 0, 80)) # Shadow
    draw.text((text_x, text_y), text, font=font, anchor='mm', fill=(255, 255, 255, 255)) # Main

def process_image(filename):
    if not (filename.lower().endswith('.png') or filename.lower().endswith('.jpg')):
        return

    # 1. Load Original
    file_path = os.path.join(INPUT_DIR, filename)
    img = Image.open(file_path).convert("RGBA")

    # 1.1 Crop iOS-specific system bars (Status bar at top, Home bar at bottom)
    # This is essential to pass Huawei/Android reviews
    top_crop = int(img.height * 0.048) # Removes time, wifi, battery
    bottom_crop = int(img.height * 0.035) # Removes the black Home Indicator line
    img = img.crop((0, top_crop, img.width, img.height - bottom_crop))

    # 2. Create Artistic Background
    bg = create_gradient(TARGET_SIZE[0], TARGET_SIZE[1], COLOR_START, COLOR_END)
    bg = add_patterns(bg)

    # 3. Add Headline
    draw_headline(bg, filename)

    # 4. Resize Screenshot
    avail_w = TARGET_SIZE[0] - (PADDING_SIDE * 2) - (FRAME_BEZEL_THICKNESS * 2)
    avail_h = TARGET_SIZE[1] - (PADDING_TOP + PADDING_BOTTOM) - (FRAME_BEZEL_THICKNESS * 2)
    
    scale = min(avail_w / img.width, avail_h / img.height)
    new_w = int(img.width * scale)
    new_h = int(img.height * scale)
    
    img_resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    # 5. Wrap in Phone Frame
    img_framed = create_phone_frame(img_resized)

    # 6. Create Shadow
    shadow = create_drop_shadow(
        img_framed.size, 
        SHADOW_BLUR_RADIUS, 
        SHADOW_OFFSET, 
        SHADOW_OPACITY
    )

    # 7. Composite (Shoved down to leave room for text)
    dev_x = (TARGET_SIZE[0] - img_framed.width) // 2
    dev_y = TARGET_SIZE[1] - PADDING_BOTTOM - img_framed.height
    
    # Shadow Position
    shadow_x = dev_x - (shadow.width - img_framed.width) // 2 + SHADOW_OFFSET[0]
    shadow_y = dev_y - (shadow.height - img_framed.height) // 2 + SHADOW_OFFSET[1]
    
    bg.paste(shadow, (shadow_x, shadow_y), shadow)
    
    # Paste Framed Device
    bg.paste(img_framed, (dev_x, dev_y), img_framed)

    # 8. Save
    output_path = os.path.join(OUTPUT_DIR, filename)
    bg.convert("RGB").save(output_path)
    print(f"Processed: {filename} -> {output_path}")

def main():
    print(f"Creating artistic screenshots from {INPUT_DIR}...")
    files = os.listdir(INPUT_DIR)
    for f in files:
        process_image(f)
    print("Done.")

if __name__ == '__main__':
    main()
