def is_chinese(uchar):
    """判断一个unicode是否是汉字,或汉字标点"""
    if (uchar >= u'\u4e00' and uchar <= u'\u9fa5') or (uchar >= u'\uff00' and uchar <= u'\uffef') or (uchar >= u'\u3000' and uchar <= u'\u303f'):
        return True
    else:
        return False

def align( text, width, just = "left" ):
    """对指定字符串用空格进行左补齐或右补齐，使其达到指定长度"""
    stext = str(text)
    count = 0
    for u in text:
        if is_chinese(u):
            count += 2 # 计算中文字符占用的宽度
        else:
            count += 1  # 计算英文字符占用的宽度
    if just == "right":
        return " " * (width - count ) + text
    elif just == "left":
        return text + " " * ( width - count )

def string_ljust( text, width ):
    return align( text, width, "left" )


def string_rjust( text, width ):
    return align( text, width, "right" )

