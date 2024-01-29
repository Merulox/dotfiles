import mpv
import os

def capture_metadata():
    player = mpv.MPV()
    metadata = player.metadata.get()

    if 'title' in metadata:
        return metadata['title']
    elif 'filename' in metadata:
        return os.path.splitext(os.path.basename(metadata['filename']))[0]
    else:
        return 'unknown'

if __name__ == "__main__":
    print(capture_metadata())

