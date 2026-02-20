#!/usr/bin/env python3
import os, sys, requests, textwrap

API_KEY = os.environ.get('NOTION_SMARTENVIOS_API_KEY')
if not API_KEY:
    print('Missing NOTION_SMARTENVIOS_API_KEY', file=sys.stderr)
    sys.exit(1)

if len(sys.argv) != 3:
    print('Usage: notion_export_recursive.py <page_id> <output_file>', file=sys.stderr)
    sys.exit(1)

PAGE_ID = sys.argv[1].replace('-', '')
OUTPUT = sys.argv[2]
BASE_URL = 'https://api.notion.com/v1'
HEADERS = {
    'Authorization': f'Bearer {API_KEY}',
    'Notion-Version': '2025-09-03'
}

visited = set()

def fetch_json(method, path, params=None):
    resp = requests.request(method, f'{BASE_URL}{path}', headers=HEADERS, params=params)
    resp.raise_for_status()
    return resp.json()

def get_title(page_id):
    data = fetch_json('GET', f'/pages/{page_id}')
    props = data.get('properties', {})
    for key in ('title', 'Name'):
        prop = props.get(key)
        if prop and prop.get('type') == 'title':
            title = ''.join(rt.get('plain_text', '') for rt in prop.get('title', []))
            if title:
                return title
    return data.get('id', 'Untitled')

def rich_text_to_md(rich_text):
    parts = []
    for rt in rich_text or []:
        text = rt.get('plain_text', '')
        annotations = rt.get('annotations', {})
        if annotations.get('code'):
            text = f'`{text}`'
        if annotations.get('bold'):
            text = f'**{text}**'
        if annotations.get('italic'):
            text = f'*{text}*'
        if annotations.get('strikethrough'):
            text = f'~~{text}~~'
        if annotations.get('underline'):
            text = f'<u>{text}</u>'
        if rt.get('href'):
            text = f'[{text}]({rt["href"]})'
        parts.append(text)
    return ''.join(parts).strip()

def render_block(block, depth=0):
    btype = block.get('type')
    data = block.get(btype, {})
    if btype == 'paragraph':
        text = rich_text_to_md(data.get('rich_text'))
        return text + '\n'
    if btype == 'heading_1':
        return f'# {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'heading_2':
        return f'## {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'heading_3':
        return f'### {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'bulleted_list_item':
        return f'- {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'numbered_list_item':
        return f'1. {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'to_do':
        chk = 'x' if data.get('checked') else ' '
        return f'- [{chk}] {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'quote':
        return f'> {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'code':
        lang = data.get('language') or ''
        text = ''.join(rt.get('plain_text', '') for rt in data.get('rich_text', []))
        return f'```{lang}\n{text}\n```\n'
    if btype == 'divider':
        return '---\n'
    if btype == 'callout':
        return f'> 💬 {rich_text_to_md(data.get("rich_text"))}\n'
    if btype == 'child_page':
        child_id = block['id'].replace('-', '')
        if child_id in visited:
            return ''
        visited.add(child_id)
        title = data.get('title', 'Untitled')
        content = export_page(child_id, heading_level=min(depth+2, 6))
        return f'## {title}\n\n{content}\n'
    return ''

def export_page(page_id, heading_level=1):
    lines = []
    cursor = None
    while True:
        params = {'page_size': 100}
        if cursor:
            params['start_cursor'] = cursor
        resp = fetch_json('GET', f'/blocks/{page_id}/children', params)
        for block in resp.get('results', []):
            lines.append(render_block(block, heading_level))
            if block.get('has_children') and block.get('type') not in ('child_page',):
                block_id = block['id'].replace('-', '')
                lines.append(export_page(block_id, heading_level+1))
        if resp.get('has_more'):
            cursor = resp.get('next_cursor')
        else:
            break
    return '\n'.join(filter(None, lines))

def main():
    title = get_title(PAGE_ID)
    body = export_page(PAGE_ID)
    with open(OUTPUT, 'w', encoding='utf-8') as f:
        f.write(f'# {title}\n\n')
        f.write(f'Source: https://notion.so/{PAGE_ID}\n')
        f.write(f'Exported: {os.popen("date -u +%Y-%m-%dT%H:%M:%SZ").read().strip()}\n\n')
        f.write(body)

if __name__ == '__main__':
    main()
