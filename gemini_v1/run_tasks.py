import os
import re
import subprocess
import sys

def run_gemini(prompt):
    """Calls the gemini CLI with a prompt and returns the output."""
    try:
        # Use -p for non-interactive mode
        result = subprocess.run(
            ["gemini", "-p", prompt],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error calling gemini: {e.stderr}", file=sys.stderr)
        return None

def main():
    if not os.path.exists("whitepaper.md"):
        print("whitepaper.md not found.")
        sys.exit(1)

    with open("whitepaper.md", "r") as f:
        content = f.read()

    # Extract goals/purpose and workflow for context
    context_match = re.search(r"## goal, purpose(.*?)(?=# base|Checklist/Plan:)", content, re.S)
    context = context_match.group(0) if context_match else ""

    # Extract tasks
    # Regex to match: 1. task name
    # We want to catch the number and the name
    tasks = re.findall(r"^\s*(\d+)\.\s*(.+)$", content, re.M)

    if not tasks:
        print("No tasks found in whitepaper.md.")
        sys.exit(1)

    print(f"Found {len(tasks)} tasks.")

    for num_str, task_name in tasks:
        num = int(num_str)
        # Sanitize task name for filename
        safe_name = re.sub(r"[^a-zA-Z0-9\s]", "", task_name).strip().replace(" ", "_").lower()
        filename = f"{num:02d}_{safe_name}.md"

        if os.path.exists(filename):
            print(f"Skipping {filename} (already exists)")
            continue

        print(f"Processing task {num}: {task_name}...")

        prompt = f"""
You are an expert system administrator and DevOps engineer specializing in Fedora bootc, Podman, and system automation.

CONTEXT from the whitepaper:
{context}

TASK: {num}. {task_name}

INSTRUCTION:
Study this item and find the best approach based on the context provided.
Create a detailed markdown document titled "{num}. {task_name}".
The document's main goal is to include and explain all code necessary to complete the task.
Provide clear, actionable steps, Containerfiles, Quadlet files, shell scripts, or commands as appropriate.
Ensure the approach aligns with the "bootc image" and "podman quadlet" strategy described in the whitepaper.

Return ONLY the markdown document content.
"""
        response = run_gemini(prompt)
        
        if response:
            with open(filename, "w") as f:
                f.write(response)
            print(f"Saved to {filename}")
        else:
            print(f"Failed to get response for task {num}")

if __name__ == "__main__":
    main()
