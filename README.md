# Clientes Nim para o Needle

O Needle não possui uma API Nim nativa. Este exemplo usa o endpoint local
`/generate` que o comando `needle playground` expõe e executa a ferramenta
retornada em Nim.

Se ainda não clonou o projeto, prepare-o assim:

```bash
git clone https://github.com/cactus-compute/needle.git
cd needle
source ./setup
```

Em um terminal, na raiz do repositório, inicie o playground:

```bash
source .venv/bin/activate
needle playground
```

Em outro terminal:

```bash
nim c -r examples/nim/needle_client.nim
nim c -r examples/nim/needle_client.nim -- "Acenda as luzes do quarto"
```

O cliente envia a consulta e o schema `control_lights` para
`http://127.0.0.1:7860/generate`. O modelo apenas escolhe a ferramenta e
produz os argumentos; a função `controlLights` é o ponto em que uma aplicação
real deve validar e executar a ação.

O exemplo usa somente a biblioteca padrão do Nim. A resposta do Needle tem a
forma `{"result":"[...]"}`: por isso o código faz `parseJson` duas vezes.

## Variante com DSPy importado em Nim

`dspy_needle.nim` é o cabeçalho reutilizável: contém o macro `dspyModule`,
os templates de assinatura/Chain-of-Thought e o transporte Needle
(endpoint + tools). A assinatura fica dentro do módulo, logo após a docstring,
como `dspySignature ToolReasoningSignature, chain:` (ou `forward` / `react`), com
blocos `input` e `output`. O macro injeta o contrato em `this.signature` e o
módulo recebe um bloco `forward:` com sua lógica, como em DSPy.

Para importar `dspy` no próprio Nim, use `nimpy`. O arquivo
`examples/nim/dspy_client.nim` faz `pyImport("dspy")`, instancia
`dspy.LM`, `dspy.ChainOfThought` e chama o módulo diretamente a partir do Nim
para validar a ferramenta antes da execução local. Não há bootstrap nem arquivo
Python auxiliar.

`DspyToolReasoner` modela a semântica de um `dspy.Module`: o construtor
configura o LM e cria o predictor, enquanto `forward` recebe as entradas e
devolve a Prediction normalizada. A assinatura é declarada com o template
`dspySignature(...)`, e `dspyChainOfThought(...)` instancia o predictor a
partir dela.

Pré-requisitos:

```bash
source .venv/bin/activate
python -m pip install -U dspy
nimble install nimpy
export DSPY_MODEL=openai/gpt-4o-mini
```

Execução:

```bash
nim c -r examples/nim/dspy_client.nim
nim c -r examples/nim/dspy_client.nim -- "Acenda as luzes do quarto"
```

Essa variante não depende de um `examples/dspy/*.py`; o Nim continua sendo o
ponto que configura e chama o DSPy e executa `controlLights`.
módulo. O endpoint padrão é `NeedleEndpoint` (`127.0.0.1:7860/generate`); no
`main`, basta passar o modelo e `controlLightsTools()`. Um endpoint alternativo
pode ser passado como terceiro argumento do construtor gerado.
O `forward` gerado recebe explicitamente `(request: string, candidate: JsonNode)`.
Um módulo pode chamar outro diretamente dentro desse bloco, por exemplo
`other.forward(request, candidate)`. O `main` apenas obtém a saída do Needle e
faz a primeira chamada do módulo.
