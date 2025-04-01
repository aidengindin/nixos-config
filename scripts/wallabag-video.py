import subprocess
import re
import sys

def run_wallabag_command(args):
    try:
        # Run with both stdout and stderr captured
        result = subprocess.run(['wallabag'] + args, 
                                capture_output=True, 
                                text=True,
                                check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing wallabag command: {e}")
        print(f"stderr: {e.stderr}")
        sys.exit(1)

# Get video list
print("Fetching video list...")
output = run_wallabag_command(['list', '-n', '-g', 'video'])

# Process the output, filtering out spinner characters
videos = []
# Split by newlines and filter out empty lines and spinner characters
lines = [line for line in output.split('\n') if line.strip() and not re.match(r'^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]$', line.strip())]

for line in lines:
    # Skip divider lines
    if line.startswith('-'):
        continue
    
    # Try to extract ID and title using regex
    match = re.match(r'(\d+)\s+(.*)', line)
    if match:
        video_id, title = match.groups()
        videos.append({'id': video_id, 'title': title.strip()})
    else:
        print(f"Warning: Could not parse line: {line}")

if not videos:
    print("No videos found or could not parse the output.")
    print("Raw output:")
    print(output)
    sys.exit(1)

# Display videos
for i, video in enumerate(videos):
    print(f"{i}: {video['title']}")

# Get user selection
while True:
    try:
        selection = input('Choose a video (number): ')
        selection_idx = int(selection)
        if 0 <= selection_idx < len(videos):
            break
        print(f"Please enter a number between 0 and {len(videos)-1}")
    except ValueError:
        print("Please enter a valid number")

video_id = videos[selection_idx]['id']
print(f"Selected video ID: {video_id}")

# Get video details
print("Fetching video details...")
info_output = run_wallabag_command(['info', video_id])

# Find the URL line using regex
url_match = re.search(r'Url\s*:\s*(https?://\S+)', info_output)
if url_match:
    url = url_match.group(1)
    subprocess.run(["mpv", url], capture_output=True)
else:
    print("URL not found in the output")
    print("Raw info output:")
    print(info_output)

choice = input("Mark entry as read? [Y/n] ")
if choice.lower() != "n":
    run_wallabag_command(["read", video_id])
    print("Entry marked as read.")

