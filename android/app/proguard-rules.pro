# R8 rules for the release build.
#
# Almost everything this app does across a process boundary is resolved by
# *name* at runtime: jUPnP finds service actions by reading annotations, and
# the audio engine is reached over JNI, which links C functions to Kotlin
# methods by their mangled names. R8 renames and removes what looks unused, and
# nothing here looks used -- no Kotlin code calls these methods.
#
# That failure mode is the dangerous part. It does not break the build; it
# builds, installs, and then the renderer is invisible to controllers or dies
# with UnsatisfiedLinkError the first time a track plays. A release build must
# be run on a real device before it is uploaded anywhere.

# --- OSGi annotations ------------------------------------------------------
#
# jUPnP is also published as an OSGi bundle and carries @Component and
# @Designate for containers that read them. They are compile-time only, Android
# has no OSGi container, and the classes are genuinely absent. This is the
# warning that stops the build; the rules below are the ones that matter.
-dontwarn org.osgi.**

# --- JNI -------------------------------------------------------------------
#
# NativeBridge declares 24 `external fun`s. JNI resolves each to a C symbol
# built from the class and method name -- Java_com_hifirend_NativeBridge_
# nativeStartStream and so on -- so renaming either end breaks the link at the
# moment audio is first asked for, with nothing wrong at compile time.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keep class com.hifirend.NativeBridge { *; }

# --- jUPnP service binding -------------------------------------------------
#
# AnnotationLocalServiceBinder reads @UpnpService, @UpnpAction and
# @UpnpStateVariable off our OpenHome classes and builds the UPnP service
# description from the method and parameter names it finds. Renaming a method
# renames the action a controller invokes, and stripping one it thinks is
# unused removes the action entirely -- a renderer that advertises itself and
# then answers nothing.
#
# Kept broadly and deliberately: the annotated surface *is* the network
# contract, and being wrong here is invisible until a controller fails to drive
# the renderer.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod,
                RuntimeVisibleAnnotations, RuntimeVisibleParameterAnnotations,
                RuntimeInvisibleAnnotations, RuntimeInvisibleParameterAnnotations,
                MethodParameters

-keep class com.hifirend.upnp.** { *; }
-keep @org.jupnp.binding.annotations.UpnpService class * { *; }

# jUPnP reflects over its own model and instantiates protocol and transport
# classes by name from its configuration.
-keep class org.jupnp.** { *; }
-dontwarn org.jupnp.**

# RendererAvTransport extends AbstractAVTransportService, whose action methods
# are bound the same reflective way through the support package.
-keep class org.jupnp.support.** { *; }

# --- Kotlin metadata -------------------------------------------------------
#
# jUPnP inspects parameter types and generic signatures when building action
# arguments; Kotlin's metadata is what keeps those readable.
-keep class kotlin.Metadata { *; }
