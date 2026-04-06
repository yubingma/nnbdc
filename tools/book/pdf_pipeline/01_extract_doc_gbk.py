import re
import nltk

def is_valid_english_word(word):
    """检查是否是有效的英语单词"""
    if not word or len(word) < 2 or len(word) > 25:
        return False
    
    # 过滤掉全是相同字母的词
    if len(set(word)) == 1:
        return False
    
    # 过滤掉包含连续超过2个相同字母的词
    if re.search(r'(.)\1{2,}', word):
        return False
    
    # 过滤掉数字
    if re.search(r'\d', word):
        return False
    
    # 过滤掉以-开头或结尾的
    if word.startswith('-') or word.endswith('-'):
        return False
    
    # 过滤掉包含大写字母的（除非是全大写的缩写词）
    if any(c.isupper() for c in word[1:]):
        return False
    
    return True

# 需要排除的乱码词列表（基于scout报告）
GARBAGE_WORDS = {
    'bbduoic', 'bdfzh', 'vcknxv', 'rabcefgijlmoqrsuvx',  # 明显乱码
    'heshe', 'itsit', 'shesshe', 'whatswhat',  # 乱码
    'ofevid', 'tfgv', 'rbgq', 'sudx', 'temv', 'tweg', 'uoic', 'vpjd',  # 乱码
    'ysmga', 'ysnhc', 'zheh', 'yjrv', 'yvpk', 'ofew', 'wweg', 'rbev', 'whos',  # 乱码
    'lenovo', 'tiananmen', 'normaldotm', 'wingdings',  # 系统元数据
}

def extract_from_doc_gbk_final(input_path, output_path):
    words = set()
    
    with open(input_path, 'rb') as f:
        data = f.read()
    
    try:
        text = data.decode('gbk')
    except:
        try:
            text = data.decode('gb2312')
        except:
            text = data.decode('latin-1', errors='ignore')
    
    print(f"文本长度: {len(text)} 字符")
    
    # 加载 NLTK 词典
    try:
        from nltk.corpus import words as nltk_words
        english_dict = set(nltk_words.words())
    except:
        nltk.download('words', quiet=True)
        from nltk.corpus import words as nltk_words
        english_dict = set(nltk_words.words())
    
    # 扩展字典 - 小学英语常见词
    common_words = {'maths', 'centre', 'auntie', 'granny', 'grandma', 'grandpa', 'hello', 'hi', 'hey', 
                   'gonna', 'wanna', 'gotta', 'kinda', 'sorta', 'dunno', 'lemme', 'gimme', 'outta', 'lotsa',
                   'awhile', 'anymore', 'everytime', 'sometime', 'anytime', 'another', 'moreover', 'however',
                   'bye', 'goodbye', 'tes', 'tonight', 'night', 'afternoon', 'morning', 'evening',
                   'bedroom', 'classroom', 'bathroom', 'livingroom', 'kitchen', 'diningroom', 'homework', 'birthday',
                   'balloon', 'basketball', 'baseball', 'football', 'volleyball', 'headphone', 'keyboard', 'weekend',
                   'weekday', 'sunny', 'cloudy', 'rainy', 'snowy', 'windy', 'fresh',
                   'delicious', 'lovely', 'beautiful', 'wonderful', 'amazing', 'awesome', 'great', 'fantastic',
                   'happy', 'sad', 'angry', 'tired', 'excited', 'nervous', 'scared', 'surprised', 'bored', 'hungry',
                   'thirsty', 'sick', 'healthy', 'strong', 'weak', 'fast', 'slow', 'quick', 'easy', 'difficult',
                   'interesting', 'boring', 'funny', 'serious', 'clever', 'silly', 'noisy', 'quiet', 'clean', 'dirty',
                   'empty', 'full', 'light', 'heavy', 'soft', 'hard', 'smooth', 'rough', 'wet', 'dry', 'dark', 'bright',
                   'loud', 'softly', 'quickly', 'slowly', 'carefully', 'careful', 'happy', 'luckily', 'usually',
                   'sometimes', 'always', 'never', 'ever', 'still', 'already', 'yet', 'just', 'only', 'also', 'too',
                   'very', 'really', 'quite', 'rather', 'almost', 'nearly', 'exactly', 'especially', 'finally',
                   'absolutely', 'completely', 'probably', 'possibly', 'certainly', 'maybe', 'perhaps', 'actually',
                   'basically', 'clearly', 'obviously', 'certainly', 'definitely', 'exactly', 'simply', 'hopefully',
                   'thankyou', 'thank', 'thanks', 'sorry', 'please', 'welcome', 'congratulations', 'good luck',
                   'goodbye', 'see you', 'how are you', 'what time', 'what about', 'what for', 'how much', 'how many',
                   'how long', 'how far', 'how old', 'what colour', 'what kind', 'what sort', 'what size', 'what shape',
                   'what season', 'what weather', 'what day', 'what date', 'what month', 'what year', 'what temperature',
                   'busy', 'careful', 'wonderful', 'beautiful', 'delicious', 'difficult', 'different', 'dangerous',
                   'important', 'interesting', 'exciting', 'surprising', 'bored', 'tired', 'excited', 'worried',
                   'Australian', 'Canadian', 'Chinese', 'Japanese', 'American', 'British', 'European', 'African',
                   'Indian', 'Russian', 'French', 'German', 'Spanish', 'Italian', 'Korean', 'Brazilian', 'Mexican',
                   'hospital', 'station', 'police', 'office', 'school', 'university', 'library', 'museum', 'park',
                   'garden', 'beach', 'mountain', 'island', 'country', 'city', 'town', 'village', 'street', 'road',
                   'restaurant', 'cafeteria', 'bookshop', 'supermarket',
                   'hat', 'cap', 'glove', 'scarf', 'umbrella', 'purse', 'wallet', 'bag', 'box', 'bottle', 'cup', 'glass',
                   'plate', 'bowl', 'spoon', 'fork', 'knife', 'chopsticks', 'napkin', 'table', 'chair', 'desk', 'bed',
                   'sofa', 'couch', 'carpet', 'curtain', 'window', 'door', 'floor', 'ceiling', 'wall', 'roof', 'house',
                   'home', 'room', 'floor', 'stair', 'gate', 'fence', 'yard', 'garden', 'tree', 'flower', 'grass', 'leaf',
                   'plant', 'seed', 'soil', 'water', 'sun', 'moon', 'star', 'sky', 'cloud', 'rain', 'snow', 'wind', 'fog',
                   'air', 'fire', 'earth', 'sea', 'ocean', 'river', 'lake', 'pond', 'stream', 'hill', 'mountain', 'valley',
                   'forest', 'wood', 'jungle', 'desert', 'beach', 'island', 'coast', 'shore', 'wave', 'fish', 'bird',
                   'dog', 'cat', 'horse', 'cow', 'pig', 'sheep', 'chicken', 'duck', 'goose', 'rabbit', 'mouse', 'rat',
                   'snake', 'fish', 'whale', 'dolphin', 'shark', 'tiger', 'lion', 'bear', 'elephant', 'monkey', 'panda',
                   'zebra', 'giraffe', 'penguin', 'kangaroo', 'koala', 'squirrel', 'frog', 'toad', 'turtle',
                   'snail', 'worm', 'butterfly', 'bee', 'ant', 'spider', 'bug', 'beetle', 'fly', 'mosquito',
                   'sandwich', 'pizza', 'hamburger', 'hotdog', 'noodle', 'rice', 'bread', 'egg', 'meat', 'chicken', 'beef',
                   'pork', 'fish', 'vegetable', 'fruit', 'apple', 'banana', 'orange', 'grape', 'pear', 'peach', 'melon',
                   'watermelon', 'strawberry', 'blueberry', 'cherry', 'lemon', 'mango', 'pineapple', 'coconut', 'juice',
                   'milk', 'water', 'tea', 'coffee', 'soda', 'cola', 'lemonade', 'beer', 'wine', 'soup', 'salad', 'cake',
                   'cookie', 'candy', 'chocolate', 'icecream', 'pie', 'pudding', 'jam', 'honey', 'butter', 'cheese',
                   'salt', 'pepper', 'sugar', 'oil', 'vinegar', 'mustard', 'ketchup', 'sauce', 'seasoning', 'spice',
                   'breakfast', 'lunch', 'dinner', 'supper', 'snack', 'food', 'meal', 'menu', 'table', 'restaurant',
                   'fork', 'spoon', 'knife', 'plate', 'bowl', 'cup', 'glass', 'bottle', 'napkin', 'tray', 'menu',
                   'bill', 'tip', 'order', 'book', 'reserve', 'table', 'waiter', 'waitress', 'chef', 'cook', 'kitchen',
                   'bus', 'car', 'taxi', 'truck', 'van', 'motorcycle', 'bicycle', 'train', 'subway', 'metro', 'plane',
                   'airplane', 'jet', 'helicopter', 'ship', 'boat', 'ferry', 'sailboat', 'yacht', 'rocket', 'spaceship',
                   'traffic', 'road', 'street', 'avenue', 'highway', 'freeway', 'expressway', 'motorway', 'route',
                   'journey', 'trip', 'travel', 'tour', 'visit', 'stay', 'arrive', 'leave', 'depart', 'return', 'come',
                   'go', 'move', 'walk', 'run', 'jump', 'skip', 'hop', 'climb', 'crawl', 'swim', 'dive', 'float', 'fly',
                   'drive', 'ride', 'cycle', 'sail', 'land', 'park', 'stop', 'wait', 'hurry', 'rush',
                   'early', 'late', 'on time', 'quick', 'slow', 'fast', 'sudden', 'suddenly', 'quickly', 'slowly',
                   'carefully', 'careless', 'easily', 'hardly', 'barely', 'just', 'only', 'even', 'still', 'also', 'too',
                   'as well', 'either', 'neither', 'both', 'all', 'some', 'any', 'many', 'much', 'lots of', 'plenty of',
                   'few', 'little', 'a few', 'a little', 'several', 'most', 'almost', 'nearly', 'approximately', 'about',
                   'around', 'exactly', 'precisely', 'right', 'correct', 'wrong', 'incorrect', 'right', 'left', 'front',
                   'back', 'up', 'down', 'in', 'out', 'inside', 'outside', 'over', 'under', 'above', 'below', 'between',
                   'among', 'through', 'across', 'along', 'around', 'near', 'far', 'close', 'next to', 'beside',
                   'in front of', 'behind', 'on the left', 'on the right', 'on the corner', 'at the corner',
                   'across from', 'opposite', 'against', 'toward', 'away from', 'from', 'to', 'into', 'onto', 'out of',
                   'off', 'on', 'at', 'in', 'by', 'with', 'without', 'about', 'after', 'before', 'during', 'while',
                   'when', 'where', 'how', 'why', 'what', 'which', 'who', 'whom', 'whose', 'whether', 'if',
                   'because', 'although', 'though', 'unless', 'until', 'since', 'as', 'like', 'than', 'for', 'of',
                   'again', 'further', 'then', 'once', 'here', 'there', 'where', 'when', 'why', 'how', 'all', 'both',
                   'each', 'few', 'more', 'most', 'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same',
                   'so', 'than', 'too', 'very', 'can', 'could', 'should', 'would', 'may', 'might', 'must', 'shall',
                   'will', 'do', 'does', 'did', 'have', 'has', 'had', 'having', 'be', 'been', 'being', 'is', 'are',
                   'was', 'were', 'am', 'become', 'begin', 'bend', 'blow', 'break', 'bring', 'build', 'buy',
                   'catch', 'choose', 'come', 'cost', 'cut', 'deal', 'dig', 'draw', 'drink', 'drive', 'eat',
                   'fall', 'feel', 'fight', 'find', 'fly', 'forget', 'forgive', 'freeze', 'get', 'give', 'go', 'grow',
                   'hang', 'have', 'hear', 'hide', 'hit', 'hold', 'hurt', 'keep', 'know', 'learn', 'leave', 'lend',
                   'let', 'lie', 'lose', 'make', 'mean', 'meet', 'mistake', 'pay', 'put', 'read', 'ride', 'ring',
                   'rise', 'run', 'say', 'see', 'sell', 'send', 'set', 'shall', 'show', 'shut', 'sing', 'sit', 'sleep',
                   'speak', 'spend', 'stand', 'steal', 'stick', 'strike', 'swear', 'sweep', 'swim', 'take', 'teach',
                   'tell', 'think', 'throw', 'understand', 'wake', 'wear', 'win', 'write', 'won', 'done', 'got',
                   'come', 'came', 'went', 'gone', 'did', 'done', 'saw', 'seen', 'knew', 'known', 'thought', 'told',
                   'taught', 'bought', 'sold', 'brought', 'caught', 'left', 'lost', 'built', 'meant', 'sent', 'spent',
                   'a', 'an', 'the', 'and', 'or', 'but', 'if', 'because', 'although', 'while', 'when', 'where',
                   'how', 'what', 'which', 'who', 'whom', 'whose', 'that', 'this', 'these', 'those', 'i', 'you',
                   'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'its',
                   'our', 'their', 'mine', 'yours', 'hers', 'ours', 'theirs', 'myself', 'yourself', 'himself',
                   'herself', 'itself', 'ourselves', 'themselves', 'one', 'some', 'any', 'no', 'none', 'every',
                   'each', 'either', 'neither', 'both', 'all', 'much', 'many', 'more', 'most', 'few', 'little',
                   'less', 'least', 'several', 'enough', 'plenty', 'one', 'two', 'three', 'four', 'five', 'six',
                   'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
                   'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
                   'eighty', 'ninety', 'hundred', 'thousand', 'million', 'billion', 'first', 'second', 'third',
                   'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'last', 'next', 'other',
                   'another', 'same', 'different', 'new', 'old', 'young', 'big', 'small', 'large', 'little', 'tiny',
                   'huge', 'giant', 'great', 'good', 'bad', 'nice', 'kind', 'lovely', 'pretty', 'ugly', 'awful',
                   'terrible', 'horrible', 'fine', 'okay', 'alright', 'sure', 'certainly',
                   # 额外添加一些常见词
                   'tangyuan', 'tiananmen',  # 中文专有名词
    }
    
    english_dict.update(common_words)
    
    lines = text.split('\n')
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        parts = re.split(r'[,，;；\s\n\r\t\(\)（）\[\]【】]+', line)
        
        for part in parts:
            if not part:
                continue
            
            english_part = re.split(r'[\(（\[【\u4e00-\u9fa5]', part)[0].strip()
            english_part = re.sub(r'[^a-zA-Z\-]', '', english_part)
            
            if english_part and is_valid_english_word(english_part):
                lower_word = english_part.lower()
                
                # 排除乱码词表
                if lower_word in GARBAGE_WORDS:
                    continue
                
                # 必须是字典中的词，或者长度>=4且符合字母组合模式
                if lower_word in english_dict or (len(lower_word) >= 4 and len(set(lower_word)) >= 3):
                    # 额外过滤掉明显的乱码模式
                    if not re.search(r'^[a-z]{1,2}[bdfghjklmnpqrstvwxyz]{5,}[a-z]{0,2}$', lower_word):
                        words.add(lower_word)
    
    unique_words = sorted(list(words))
    
    with open(output_path, 'w', encoding='utf-8') as f:
        for w in unique_words:
            f.write(w + "\n")
    
    print(f"✅ 提取完成！共 {len(unique_words)} 个单词。")
    print(f"最终结果已保存至: {output_path}")

if __name__ == '__main__':
    extract_from_doc_gbk_final('/Volumes/ssd/ppdc/tools/book/小学/译林版/最新译林版小学英语三-六年级单词汇总.doc', '/Volumes/ssd/ppdc/tools/book/pdf_pipeline/yilin_raw.txt')
