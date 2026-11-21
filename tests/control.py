from functools import cache
from pathlib import Path

from pyslang import ast, syntax


@cache
def _control_fields():
    source = Path(__file__).resolve().parents[1] / "tinycpu.sv"
    compilation = ast.Compilation()
    compilation.addSyntaxTree(syntax.SyntaxTree.fromFile(str(source)))
    typedef = compilation.getRoot().compilationUnits[0].find("Control")
    if typedef is None or not isinstance(typedef.canonicalType, ast.PackedStructType):
        raise ValueError(f"Expected a packed struct named Control in {source}")

    fields = {}
    for field in typedef.canonicalType:
        field_type = field.type.canonicalType
        literals = {}
        if isinstance(field_type, ast.EnumType):
            literals = {item.name: int(item.value.value) for item in field_type}
        fields[field.name] = (field.bitOffset, field_type.bitWidth, literals)
    return fields


def control(**values: int | str) -> int:
    """Pack one Control word. Omitted fields are zero."""
    fields = _control_fields()
    word = 0
    for name, value in values.items():
        offset, width, literals = fields[name]
        if isinstance(value, str):
            if value not in literals:
                raise ValueError(f"{name} has no enum literal {value!r}")
            value = literals[value]
        if not 0 <= value < (1 << width):
            raise ValueError(f"{name}={value} does not fit in {width} bits")
        word |= value << offset
    return word
