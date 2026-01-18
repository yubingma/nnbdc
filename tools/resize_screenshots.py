import os
from PIL import Image, ImageFilter

INPUT_DIR = '/Volumes/ssd/nnbdc/devops/应用上架资源/ios'
OUTPUT_DIR = '/Volumes/ssd/nnbdc/devops/应用上架资源/huawei'
TARGET_SIZE = (450, 800)

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

def process_image(filename):
    if not (filename.lower().endswith('.png') or filename.lower().endswith('.jpg')):
        return

    file_path = os.path.join(INPUT_DIR, filename)
    img = Image.open(file_path)

    # 1. Calculate new size maintaining aspect ratio
    # We want to fit into 450x800.
    # Check aspect ratios
    target_ratio = TARGET_SIZE[0] / TARGET_SIZE[1]
    img_ratio = img.width / img.height

    if img_ratio > target_ratio:
        # Image is wider than target. Scale by width using LANCZOS
        new_width = TARGET_SIZE[0]
        new_height = int(img.height * (new_width / img.width))
    else:
        # Image is taller/narrower than target. Scale by height using LANCZOS
        new_height = TARGET_SIZE[1]
        new_width = int(img.width * (new_height / img.height))

    img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)

    # 2. Create background
    # Strategy: Use a blurred version of the original image to fill the background
    # Resize original to cover the target size
    if img_ratio > target_ratio:
        # Wider: scale by height to cover
        bg_height = TARGET_SIZE[1]
        bg_width = int(img.width * (bg_height / img.height))
    else:
        # Narrower: scale by width to cover
        bg_width = TARGET_SIZE[0]
        bg_height = int(img.height * (bg_width / img.width))

    bg_img = img.resize((bg_width, bg_height), Image.Resampling.LANCZOS)
    
    # Center crop the background to target size
    left = (bg_width - TARGET_SIZE[0]) // 2
    top = (bg_height - TARGET_SIZE[1]) // 2
    bg_img = bg_img.crop((left, top, left + TARGET_SIZE[0], top + TARGET_SIZE[1]))
    
    # Apply blur
    bg_img = bg_img.filter(ImageFilter.GaussianBlur(radius=20))

    # 3. Composite
    # Paste the resized main image onto the center of the blurred background
    paste_x = (TARGET_SIZE[0] - new_width) // 2
    paste_y = (TARGET_SIZE[1] - new_height) // 2
    
    bg_img.paste(img_resized, (paste_x, paste_y))

    # Save
    output_path = os.path.join(OUTPUT_DIR, filename)
    bg_img.save(output_path)
    print(f"Processed: {filename} -> {output_path}")

def main():
    print(f"Processing images from {INPUT_DIR} to {OUTPUT_DIR}...")
    files = os.listdir(INPUT_DIR)
    for f in files:
        process_image(f)
    print("Done.")

if __name__ == '__main__':
    main()
