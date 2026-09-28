package com.theoccess.enhancify

import androidx.core.content.FileProvider

/** Own subclass so it never clashes with plugins' FileProviders. */
class EnhancifyFileProvider : FileProvider()
