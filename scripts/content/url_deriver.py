"""url_deriver.py — the canonical imageBaseURL + imageId -> URL contract.

Pure, stateless, and deliberately trivial: this is the contract a later Swift
`KigoImageSource` (C25) will mirror exactly, so it stays a single obvious
function rather than growing configuration or edge cases.
"""


def derive_image_url(image_base_url: str, image_id: str) -> str:
    """Derives an image's URL by convention: `imageBaseURL + "/" + imageId + ".jpg"`."""
    return f"{image_base_url}/{image_id}.jpg"
