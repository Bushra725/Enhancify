package com.mai.photo.editor.app.picture.face.art.lab

import androidx.core.content.FileProvider

/** Own subclass so it never clashes with plugins' FileProviders. */
class EnhancifyFileProvider : FileProvider()
