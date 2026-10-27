"""Evidence presentation, separate from conversation routing and any future AI model."""


def build(context, question, local, guided_reply):
    observation = next((item for item in local['findings'] if item['kind'] == 'observation'), None)
    if observation and any(term in question.lower() for term in ('my notes', 'saved notes', 'saved observations', 'my measurements', 'what did i record')):
        return 'Your saved notes say: ' + observation['excerpt'] + '\n\nThese are your observations, not verified technical specifications.\n\nNext step: continue from these notes or open your saved conversation from Menu.'
    documents = [item for item in local['findings'] if item['kind'] == 'document']
    usable = next((item for item in documents if not item['stale'] and item['sufficient']), None)
    if usable:
        return ('I found a saved reference, but have not verified an answer for your exact machine.\n\n'
                'Can you confirm the full model designation and serial number on its identification label?')
    reply = guided_reply(context, question)
    if documents:
        reply += '\n\nReferences that are outdated or insufficient remain in job history.'
    return reply
