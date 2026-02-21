#!/usr/bin/env python3
import os
import json
import subprocess
from datetime import datetime

# Diretório base
BASE_DIR = '/var/www'
OUTPUT_FILE = '/var/www/openclaw/workspace/agents/einstein/knowledge/github/local-repos.md'

def get_repo_info(repo_path):
    """Obtém informações de um repositório Git"""
    info = {
        'name': os.path.basename(repo_path),
        'path': repo_path,
        'has_git': os.path.exists(os.path.join(repo_path, '.git')),
        'description': '',
        'last_commit': '',
        'branch': '',
        'remote_url': '',
        'tech_stack': [],
        'files': []
    }
    
    if not info['has_git']:
        return info
    
    try:
        # Obter descrição do README
        readme_files = ['README.md', 'README.txt', 'README']
        for readme in readme_files:
            readme_path = os.path.join(repo_path, readme)
            if os.path.exists(readme_path):
                with open(readme_path, 'r', encoding='utf-8', errors='ignore') as f:
                    first_lines = [f.readline().strip() for _ in range(5)]
                    info['description'] = ' '.join([line for line in first_lines if line])
                break
        
        # Executar comandos Git
        git_cmds = {
            'last_commit': ['git', 'log', '-1', '--format=%H %s %ad', '--date=short'],
            'branch': ['git', 'branch', '--show-current'],
            'remote_url': ['git', 'remote', 'get-url', 'origin']
        }
        
        for key, cmd in git_cmds.items():
            try:
                result = subprocess.run(cmd, cwd=repo_path, capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    info[key] = result.stdout.strip()
            except:
                pass
        
        # Detectar tecnologia
        tech_indicators = {
            'Node.js': ['package.json', 'node_modules'],
            'TypeScript': ['tsconfig.json', '.ts'],
            'Python': ['requirements.txt', 'setup.py', 'pyproject.toml'],
            'Docker': ['Dockerfile', 'docker-compose.yml'],
            'NestJS': ['nest-cli.json'],
            'Next.js': ['next.config.js'],
            'React': ['package.json'],  # Verificar dependências depois
            'Jest': ['jest.config.js', 'jest.config.ts'],
            'Prisma': ['prisma/schema.prisma'],
            'Knex': ['knexfile.js', 'knexfile.ts']
        }
        
        for tech, indicators in tech_indicators.items():
            for indicator in indicators:
                if '*' in indicator:
                    # Buscar arquivos com extensão
                    ext = indicator[1:]
                    for root, dirs, files in os.walk(repo_path):
                        for file in files:
                            if file.endswith(ext):
                                info['tech_stack'].append(tech)
                                break
                else:
                    # Verificar arquivo/diretório específico
                    check_path = os.path.join(repo_path, indicator)
                    if os.path.exists(check_path):
                        info['tech_stack'].append(tech)
        
        # Remover duplicatas
        info['tech_stack'] = list(set(info['tech_stack']))
        
        # Listar arquivos importantes
        important_files = []
        for root, dirs, files in os.walk(repo_path):
            # Ignorar node_modules e .git
            if 'node_modules' in dirs:
                dirs.remove('node_modules')
            if '.git' in dirs:
                dirs.remove('.git')
            
            for file in files:
                if file.endswith(('.md', '.json', '.js', '.ts', '.py', '.yml', '.yaml')):
                    rel_path = os.path.relpath(os.path.join(root, file), repo_path)
                    important_files.append(rel_path)
                    if len(important_files) >= 20:  # Limitar
                        break
            if len(important_files) >= 20:
                break
        
        info['files'] = important_files[:10]  # Limitar a 10 arquivos
        
    except Exception as e:
        print(f"Erro ao analisar {repo_path}: {e}")
    
    return info

def main():
    print('Inventariando repositórios GitHub locais...')
    
    # Encontrar repositórios (começando com ms.)
    repos = []
    for item in os.listdir(BASE_DIR):
        item_path = os.path.join(BASE_DIR, item)
        if os.path.isdir(item_path) and item.startswith('ms.'):
            repos.append(item_path)
    
    print(f'Encontrados {len(repos)} repositórios começando com "ms."')
    
    # Coletar informações
    repo_infos = []
    for repo_path in repos:
        print(f'  Analisando: {os.path.basename(repo_path)}')
        info = get_repo_info(repo_path)
        repo_infos.append(info)
    
    # Gerar markdown
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write('# Repositórios GitHub Locais (SmartEnvios)\n\n')
        f.write(f'Inventário gerado em: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
        f.write(f'Total de repositórios: {len(repo_infos)}\n\n')
        f.write('> **Nota:** Estes são repositórios locais encontrados em `/var/www/ms.*`\n\n')
        f.write('---\n\n')
        
        # Sumário por tecnologia
        tech_summary = {}
        for info in repo_infos:
            for tech in info['tech_stack']:
                tech_summary[tech] = tech_summary.get(tech, 0) + 1
        
        if tech_summary:
            f.write('## 📊 Sumário por Tecnologia\n\n')
            for tech, count in sorted(tech_summary.items(), key=lambda x: x[1], reverse=True):
                f.write(f'- **{tech}:** {count} repositórios\n')
            f.write('\n---\n\n')
        
        # Detalhes de cada repositório
        f.write('## 🗂️ Detalhes dos Repositórios\n\n')
        
        for i, info in enumerate(repo_infos, 1):
            f.write(f'### {i}. {info["name"]}\n\n')
            
            f.write(f'**Caminho:** `{info["path"]}`\n\n')
            
            if info['has_git']:
                f.write('**Status Git:** ✅ Repositório Git\n')
                if info['branch']:
                    f.write(f'**Branch atual:** `{info["branch"]}`\n')
                if info['remote_url']:
                    f.write(f'**Remote URL:** {info["remote_url"]}\n')
                if info['last_commit']:
                    parts = info['last_commit'].split(' ', 2)
                    if len(parts) >= 3:
                        commit_hash = parts[0][:8]
                        commit_msg = parts[1]
                        commit_date = parts[2]
                        f.write(f'**Último commit:** `{commit_hash}` - {commit_msg} ({commit_date})\n')
            else:
                f.write('**Status Git:** ❌ Não é um repositório Git\n')
            
            f.write('\n')
            
            if info['description']:
                f.write(f'**Descrição:** {info["description"]}\n\n')
            
            if info['tech_stack']:
                f.write('**Tecnologias:** ')
                f.write(', '.join(info['tech_stack']))
                f.write('\n\n')
            
            if info['files']:
                f.write('**Arquivos importantes:**\n')
                for file in info['files']:
                    f.write(f'- `{file}`\n')
                if len(info['files']) == 10:
                    f.write('- ... (mais arquivos)\n')
                f.write('\n')
            
            f.write('---\n\n')
    
    print(f'Inventário salvo em: {OUTPUT_FILE}')
    
    # Criar também um resumo JSON
    json_file = OUTPUT_FILE.replace('.md', '.json')
    with open(json_file, 'w', encoding='utf-8') as f:
        json.dump({
            'generated_at': datetime.now().isoformat(),
            'total_repos': len(repo_infos),
            'repos': repo_infos
        }, f, indent=2, ensure_ascii=False)
    
    print(f'JSON salvo em: {json_file}')

if __name__ == '__main__':
    main()