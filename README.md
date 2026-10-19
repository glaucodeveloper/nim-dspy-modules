# Nim DSPy Modules para Needle

Exemplo experimental de módulos DSPy-like em Nim. O cliente pede uma chamada de ferramenta ao Needle, valida a proposta com um módulo DSPy e só então executa a ferramenta aprovada.

## Arquivos

- `dspy_needle.nim`: declara assinaturas e módulos, chama o endpoint local do Needle e interpreta a resposta estruturada.
- `dspy_client.nim`: demonstra validação e execução de `web_search`, `fetch_url`, `control_lights` e `save_note`.

`control_lights` grava o estado em um arquivo JSON local; `save_note` grava uma nota em `notes/`. Essas funções são exemplos locais, não integração com dispositivos reais.

## Requisitos

- Nim e NimPy.
- Um ambiente Python com DSPy disponível para NimPy.
- Needle instalado e com o comando `needle playground` em execução. O endpoint padrão é `http://127.0.0.1:7860/generate`.
- A variável `DSPY_MODEL` configurada com o identificador de modelo aceito pelo ambiente DSPy.

## Executar

Em um terminal, inicie o playground do Needle. Em outro, na pasta deste repositório:

```bash
export DSPY_MODEL="seu-modelo"
nim c -r dspy_client.nim "Apague as luzes da cozinha"
```

O programa rejeita propostas recusadas pelo módulo DSPy, chamadas com nome de ferramenta alterado e ferramentas que não estejam na lista implementada.
