# My Claude Code Instructions
 
## Code Documentation and Naming Philosophy
 
- Code should be **self-documenting yet concise** with **no unnecessary comments**

    - Comments should be used as a last resort if self-documenting code is not practical in a certain situation.

    - **Use naming strategically** to self-document code, but variable names, like comments, can be incorrect (especially as code changes).

    - Therefore, **Prefer inline code** over creating variables or methods with clever names if the inline code is just as clear
 
## Code Structure & Abstraction
 
- **Maintain consistent abstraction levels** within each method

    - Don't mix high-level operations with low-level implementation details in the same method

    - Unless you are intentionally avoiding abstracting something that is clearer as inline code
 
## Tools

- TMUX is used to organize terminal work, with sessions scoped to projects/apps

- Windows within sessions separate concerns (e.g., backend window, frontend window)

- Always manage building and monitoring code through tmux windows



Commit as often as possible, ideally whenever you make a change before you finish responding
