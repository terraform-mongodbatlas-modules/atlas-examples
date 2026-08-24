from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SearchModes:
    keyword: bool = True
    vector: bool = True
    llm: bool = True

    def validate_retrieval(self) -> None:
        if self.keyword or self.vector:
            return
        msg = "At least one of keyword or vector must be enabled"
        raise ValueError(msg)


DEFAULT = SearchModes()
