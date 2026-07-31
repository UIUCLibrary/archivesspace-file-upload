$(function () {
  function updateFileVersionFields() {
    $('[name^="digital_object[file_versions]"][name$="[file_upload]"]').each(function () {
      $(this)
        .closest('.form-group')
        .hide();
    });

    $('[name^="digital_object[file_versions]"][name$="[file_uri]"]').each(function () {
      $(this)
        .prop('readonly', false)
        .removeAttr('readonly');
    });
  }

  $(updateFileVersionFields);

  const observer = new MutationObserver(updateFileVersionFields);

  observer.observe(document.body, {
    childList: true,
    subtree: true
  });
});
