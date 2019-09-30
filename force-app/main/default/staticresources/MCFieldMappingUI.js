function onLoad(fn) {
    if ((document.attachEvent && document.readyState === 'complete')
        || document.readyState !== 'loading') {
        fn();
    } else {
        document.addEventListener('DOMContentLoaded', fn);
    }
}

function setChoices(parentElement, choices) {
    Object.keys(choices).forEach(function(item) {
        var opt = document.createElement('option');
        opt.setAttribute('value', item);
        opt.innerText = choices[item];
        parentElement.appendChild(opt);
    });
}

function setGroupedChoices(selectElement, labels, choiceGroups) {
    Object.keys(choiceGroups).forEach(function(group) {
        var optGroup = document.createElement('optgroup');
        optGroup.id = group;
        optGroup.label = labels[group];
        setChoices(optGroup, choiceGroups[group]);
        selectElement.appendChild(optGroup);
    });
}

function updateFieldChoices(selectID, fieldsByObject) {
    var fieldSelect = document.getElementById(selectID);
    fieldSelect.innerHTML = '';
    setChoices(fieldSelect, fieldsByObject[this.value]);
}

function updateAttrFieldTagChoices(selectID, labels, attrFieldTagChoices) {
    var attrFieldTagSelect = document.getElementById(selectID);

    attrFieldTagSelect.innerHTML = '';
    setGroupedChoices(attrFieldTagSelect, labels, attrFieldTagChoices);

    if (this.value == 'push') {
        attrFieldTagSelect.querySelector('optgroup#mcMemberAttrs').setAttribute('disabled', '');
        attrFieldTagSelect.querySelector('optgroup#mcMergeFields').removeAttribute('disabled');
        attrFieldTagSelect.querySelector('optgroup#mcTags').removeAttribute('disabled');
        return;
    }

    // 'pull' or 'sync'
    attrFieldTagSelect.querySelector('optgroup#mcMemberAttrs').removeAttribute('disabled');
    attrFieldTagSelect.querySelector('optgroup#mcMergeFields').removeAttribute('disabled');
    attrFieldTagSelect.querySelector('optgroup#mcTags').setAttribute('disabled', '');
}

function deleteMapping(conn, mappingLabel) {
    if (!window.confirm('Are you sure?')) {
        return false;
    }

    console.log('delete mapping', mappingLabel);
    conn.metadata.delete('CustomMetadata', mappingLabel,
        function(err, results) {
            if (err) {
                console.log(err);
            }
            console.log(results);
            window.location.reload();
        }
    );
    return false;
}
