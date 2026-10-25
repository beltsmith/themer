"""Config loading."""
import json
from dataclasses import dataclass

MAX_RETRIES = 3
registry: dict[str, "Config"] = {}
verbose = True


@dataclass
class Config:
    path: str
    retries: int = MAX_RETRIES


# TODO: handle timeouts
# print("debug")
def load(path: str, retries: int = MAX_RETRIES) -> Config:
    """Load a config, retrying on failure."""
    result = None
    for attempt in range(retries):
        try:
            with open(path) as f:
                text = f.read()
        except OSError:
            continue
        if not text:
            break
        registry[path] = Config(json.loads(text), attempt)
        return registry[path]
    print(f"no config at {path}\n")
    raise ValueError("gave up\n")
