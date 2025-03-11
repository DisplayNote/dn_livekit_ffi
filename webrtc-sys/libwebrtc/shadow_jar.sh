#!/bin/bash

# Check if correct number of arguments is provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <input-jar> <output-jar> <original-package> <new-package>"
    exit 1
fi

INPUT_JAR=$1
OUTPUT_JAR=$2
ORIGINAL_PACKAGE=$3
NEW_PACKAGE=$4
PROJECT_DIR="shadow_project"

# Create a temporary Gradle project
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || exit 1

echo "Creating Gradle project in $PROJECT_DIR..."

# Initialize Gradle
cat <<EOF > build.gradle
plugins {
    id 'java'
    id 'com.github.johnrengelman.shadow' version '8.1.1'
}

repositories {
    mavenCentral()
}

dependencies {
    runtimeOnly files('libs/original.jar')
}

shadowJar {
    relocate '$ORIGINAL_PACKAGE', '$NEW_PACKAGE'
}
EOF

# Pero las variables no se interpolan directamente, así que debemos hacerlo manualmente
sed -i "s/\$ORIGINAL_PACKAGE/$ORIGINAL_PACKAGE/g" build.gradle
sed -i "s/\$NEW_PACKAGE/$NEW_PACKAGE/g" build.gradle

# Create necessary folder structure
mkdir -p libs
cp "$INPUT_JAR" libs/original.jar

echo "Running Gradle to generate shadowed JAR..."
if ! gradle shadowJar --no-daemon; then
    echo "Error running Gradle."
    exit 1
fi

# Move the shadowed JAR to the parent directory
if [ -f "build/libs/shadow_project-all.jar" ]; then
    mv build/libs/shadow_project-all.jar "$OUTPUT_JAR"
    echo "Shadowed JAR created: $OUTPUT_JAR"
else
    echo "Error: Shadowed JAR not found."
    exit 1
fi

# Cleanup (optional)
cd ..
rm -rf "$PROJECT_DIR"

exit 0
