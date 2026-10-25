"""Evidence presentation, separate from conversation routing and any future AI model."""


def build(context, question, local, guided_reply):
    observation = next((item for item in local['findings'] if item['kind'] == 'observation'), None)
    if observation and any(term in question.lower() for term in ('my notes', 'saved notes', 'saved observations', 'my measurements', 'what did i record')):
        return 'Your saved notes say: ' + observation['excerpt'] + '\n\nThese are your observations, not verified technical specifications.\n\nNext step: continue from these notes or open your saved conversation from Menu.'
    documents = [item for item in local['findings'] if item['kind'] == 'document']
    usable = next((item for item in documents if not item['stale'] and item['sufficient']), None)
    if usable:
        return ("There is a potentially useful saved reference for this question. It has not been checked against your exact machine.\n\n"
                "Saved text (not a verified specification): " + usable['excerpt'] + "\n\n"
                "Next step: open the saved reference below and confirm model, serial range, year and region before applying it.\n\n"
                "Source: " + usable['url'] + "\nRetrieved: " + usable['retrieved_at'] +
                " (saved copy, not refreshed). Verification: source read; technical applicability unverified.")
    reply = guided_reply(context, question)
    if documents:
        reply += '\n\nLocal memory: related saved material exists, but it is outdated or insufficient. It is not being used as a confirmed answer.'
    return reply
